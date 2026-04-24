import SwiftUI

public struct AnnouncementsListView: View {
    @StateObject private var viewModel: AnnouncementsListViewModel
    @Environment(SessionManager.self) private var sessionManager

    @State private var showCreate: Bool = false
    @State private var pendingDelete: Announcement?

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(viewModel: AnnouncementsListViewModel, isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel)
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
        content
            .navigationTitle("公告通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canManage {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showCreate = true
                        } label: {
                            Label("发布公告", systemImage: "plus")
                        }
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $showCreate) {
                AnnouncementCreateView(viewModel: viewModel)
            }
            .confirmationDialog(
                "确认删除",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { target in
                Button("删除", role: .destructive) {
                    Task { await viewModel.delete(target) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: { target in
                Text("将删除公告「\(target.title)」，该操作无法撤销。")
            }
            .zyErrorBanner($viewModel.errorMessage)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.items.isEmpty {
            BsEmptyState(
                title: "暂无公告",
                systemImage: "megaphone",
                description: "还没有发布任何公告"
            )
        } else {
            ScrollView {
                header
                    .padding(.horizontal, BsSpacing.lg)
                    .padding(.top, BsSpacing.sm)

                LazyVStack(spacing: BsSpacing.md) {
                    ForEach(viewModel.items) { item in
                        row(for: item)
                            .padding(.horizontal, BsSpacing.lg)
                    }
                }
                .padding(.vertical, BsSpacing.md)
            }
            .background(BsColor.pageBackground.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: BsSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .fill(LinearGradient(
                        colors: [BsColor.brandAzure, BsColor.brandMint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("公告通知")
                    .font(BsTypography.sectionTitle)
                    .foregroundStyle(BsColor.ink)
                Text("\(viewModel.items.count) 条公告")
                    .font(BsTypography.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func row(for item: Announcement) -> some View {
        BsCard(variant: .flat, padding: .none) {
            HStack(alignment: .top, spacing: BsSpacing.md) {
                avatar(for: item)

                VStack(alignment: .leading, spacing: BsSpacing.sm) {
                    HStack(spacing: BsSpacing.sm) {
                        Text(item.title)
                            .font(BsTypography.cardSubtitle)
                            .foregroundStyle(BsColor.ink)
                            .lineLimit(2)
                        priorityBadge(item.priority)
                        Spacer(minLength: 0)
                    }

                    Text(item.content)
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        HStack(spacing: BsSpacing.xs + 2) {
                            Text(item.profiles?.fullName ?? "未知")
                            Text("·")
                            Text(formatted(date: item.createdAt))
                        }
                        .font(BsTypography.caption)
                        .foregroundStyle(BsColor.inkMuted)

                        Spacer()

                        if canManage {
                            HStack(spacing: BsSpacing.xs) {
                                Button {
                                    Task { await viewModel.togglePin(item) }
                                } label: {
                                    Image(systemName: item.pinned ? "pin.slash" : "pin")
                                        .font(BsTypography.caption)
                                }
                                .buttonStyle(.borderless)
                                .help(item.pinned ? "取消置顶" : "置顶")

                                Button(role: .destructive) {
                                    pendingDelete = item
                                } label: {
                                    Image(systemName: "trash")
                                        .font(BsTypography.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                            .foregroundStyle(BsColor.inkMuted)
                        }
                    }
                }
            }
            .padding(BsSpacing.md + 2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                .stroke(BsColor.brandAzure.opacity(item.pinned ? 0.25 : 0),
                        lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if item.pinned {
                ZStack {
                    Circle().fill(BsColor.brandAzure)
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)
                .bsShadow(BsShadow.xs)
                .offset(x: 6, y: -6)
            }
        }
    }

    @ViewBuilder
    private func avatar(for item: Announcement) -> some View {
        let initial = String(item.profiles?.fullName?.prefix(1) ?? "?")
        ZStack {
            Circle().fill(BsColor.brandAzureLight)
            if let urlString = item.profiles?.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Text(initial)
                            .font(BsTypography.cardSubtitle)
                            .foregroundStyle(BsColor.brandAzure)
                    }
                }
                .clipShape(Circle())
            } else {
                Text(initial)
                    .font(BsTypography.cardSubtitle)
                    .foregroundStyle(BsColor.brandAzure)
            }
        }
        .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private func priorityBadge(_ priority: Announcement.Priority) -> some View {
        Text(priority.displayLabel)
            .font(BsTypography.captionSmall)
            .padding(.horizontal, BsSpacing.sm)
            .padding(.vertical, 3)
            .background(priority.tint.opacity(0.15))
            .foregroundStyle(priority.tint)
            .clipShape(Capsule())
    }

    private func formatted(date: Date?) -> String {
        guard let date = date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.setLocalizedDateFormatFromTemplate("MMMdHHmm")
        return formatter.string(from: date)
    }

    private var canManage: Bool {
        let role = RBACManager.shared
            .migrateLegacyRole(sessionManager.currentProfile?.role)
            .primaryRole
        switch role {
        case .admin, .superadmin: return true
        case .employee: return false
        }
    }
}
