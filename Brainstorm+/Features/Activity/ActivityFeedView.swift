import SwiftUI
import Supabase

public struct ActivityFeedView: View {
    @StateObject private var viewModel: ActivityFeedViewModel

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(viewModel: ActivityFeedViewModel, isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.isEmbedded = isEmbedded
    }

    public init(client: SupabaseClient = supabase, isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: ActivityFeedViewModel(client: client))
        self.isEmbedded = isEmbedded
    }

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: BsSpacing.xl) {
                header
                filterChips
                content
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.top, BsSpacing.md)
            .padding(.bottom, BsSpacing.xl)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
        .navigationTitle("动态")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .zyErrorBanner($viewModel.errorMessage)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: BsSpacing.md) {
            RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BsColor.brandAzure, BsColor.brandMint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "bolt.fill")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("动态")
                    .font(BsTypography.pageTitle)
                    .foregroundStyle(BsColor.ink)
                Text("团队活动流")
                    .font(BsTypography.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BsSpacing.xs + 2) {
                chip(label: "全部", isSelected: viewModel.filter == nil) {
                    viewModel.filter = nil
                }
                ForEach(FilterOption.allCases) { option in
                    chip(label: option.label, isSelected: viewModel.filter == option.type) {
                        viewModel.filter = option.type
                    }
                }
            }
        }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.selection()
            action()
        } label: {
            Text(label)
                .font(BsTypography.caption)
                .padding(.horizontal, BsSpacing.md)
                .padding(.vertical, BsSpacing.xs + 2)
                .background(
                    RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous)
                        .fill(isSelected
                              ? BsColor.brandAzure.opacity(0.1)
                              : Color.clear)
                )
                .foregroundStyle(isSelected ? BsColor.brandAzure : BsColor.inkMuted)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            skeletonList
        } else if viewModel.filteredItems.isEmpty {
            BsEmptyState(
                title: "暂无动态",
                systemImage: "bolt.circle",
                description: "还没有任何活动记录"
            )
            .padding(.top, BsSpacing.xxxl)
        } else {
            VStack(alignment: .leading, spacing: BsSpacing.xl) {
                ForEach(viewModel.grouped, id: \.label) { group in
                    groupSection(label: group.label, items: group.items)
                }
            }
        }
    }

    private var skeletonList: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xl) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: BsSpacing.md) {
                    RoundedRectangle(cornerRadius: BsRadius.xs)
                        .fill(BsColor.inkFaint.opacity(0.4))
                        .frame(width: 120, height: 12)
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: BsRadius.md - 2)
                            .fill(BsColor.inkFaint.opacity(0.25))
                            .frame(height: 56)
                    }
                }
            }
        }
    }

    // Activity timeline: vertical rule + 彩色圆点 —— 独特视觉保留
    private func groupSection(label: String, items: [ActivityItem]) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            Text(label.uppercased())
                .font(BsTypography.meta)
                .kerning(0.8)
                .foregroundStyle(BsColor.inkMuted)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(BsColor.inkFaint.opacity(0.5))
                    .frame(width: 1)
                    .padding(.leading, 20)

                VStack(spacing: BsSpacing.md) {
                    ForEach(items) { item in
                        ActivityRow(item: item)
                    }
                }
            }
        }
    }

    // MARK: - Filter registry

    private enum FilterOption: String, CaseIterable, Identifiable {
        case task, project, leave, announcement, okr

        var id: String { rawValue }

        var type: ActivityItem.ActivityType {
            switch self {
            case .task:         return .task
            case .project:      return .project
            case .leave:        return .leave
            case .announcement: return .announcement
            case .okr:          return .okr
            }
        }

        var label: String {
            switch self {
            case .task:         return "任务"
            case .project:      return "项目"
            case .leave:        return "请假"
            case .announcement: return "公告"
            case .okr:          return "OKR"
            }
        }
    }
}

// MARK: - Row

private struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: BsSpacing.md) {
            typeIcon
                .frame(width: 40, height: 40)
                .zIndex(1)

            card
        }
    }

    private var typeIcon: some View {
        let meta = ActivityTypeMeta.info(for: item.type)
        return RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous)
            .fill(meta.tint.opacity(0.12))
            .overlay(
                Image(systemName: meta.icon)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(meta.tint)
            )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            HStack(spacing: BsSpacing.sm) {
                if let actor = item.profiles, let name = actor.fullName, !name.isEmpty {
                    avatar(name: name)
                    Text(name)
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.ink)
                }
                Text(ActivityFeedViewModel.timeFormatter.string(from: item.createdAt))
                    .font(.system(.caption2))
                    .foregroundStyle(BsColor.inkMuted)
                Spacer(minLength: 0)
            }

            Text(item.description.isEmpty ? "—" : item.description)
                .font(BsTypography.caption)
                .foregroundStyle(BsColor.inkMuted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, BsSpacing.md)
        .padding(.vertical, BsSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .fill(BsColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
        .bsShadow(BsShadow.xs)
        .padding(.leading, BsSpacing.xs)
    }

    private func avatar(name: String) -> some View {
        let initial = String(name.prefix(1)).uppercased()
        return Circle()
            .fill(BsColor.brandAzure.opacity(0.15))
            .frame(width: 18, height: 18)
            .overlay(
                Text(initial)
                    .font(BsTypography.meta)
                    .foregroundStyle(BsColor.brandAzure)
            )
    }
}

// MARK: - Type → icon/tint mapping (mirrors Web TYPE_ICONS)

private enum ActivityTypeMeta {
    struct Info {
        let icon: String
        let tint: Color
    }

    static func info(for type: ActivityItem.ActivityType) -> Info {
        switch type {
        case .task:         return Info(icon: "checkmark.circle.fill",  tint: BsColor.brandAzure)
        case .project:      return Info(icon: "folder.fill",             tint: BsColor.success)
        case .leave:        return Info(icon: "calendar.badge.minus",    tint: BsColor.warning)
        case .announcement: return Info(icon: "megaphone.fill",          tint: BsColor.brandCoral)
        case .okr:          return Info(icon: "target",                  tint: BsColor.brandAzureDark)
        case .system:       return Info(icon: "bolt.fill",               tint: BsColor.inkMuted)
        }
    }
}
