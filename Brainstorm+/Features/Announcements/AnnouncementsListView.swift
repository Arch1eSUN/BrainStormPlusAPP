import SwiftUI
import UIKit

public struct AnnouncementsListView: View {
    @StateObject private var viewModel: AnnouncementsListViewModel
    @Environment(SessionManager.self) private var sessionManager

    @State private var showCreate: Bool = false
    @State private var pendingDelete: Announcement?

    /// Long-press v3:作者头像长按 → 弹 UserPreviewSheet。
    @State private var profilePreview: UserPreviewData? = nil

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
                            // Haptic removed: 用户反馈 toolbar 按钮过密震动
                            showCreate = true
                        } label: {
                            Label("发布公告", systemImage: "plus")
                        }
                        .accessibilityLabel("发布公告")
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $showCreate) {
                AnnouncementCreateView(viewModel: viewModel)
            }
            .sheet(item: $profilePreview) { user in
                UserPreviewSheet(user: user)
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
            ContentUnavailableView(
                "暂无公告",
                systemImage: "megaphone",
                description: Text("还没有发布任何公告")
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
                            // Long-press 增强 (longpress-system §3 公告项):
                            // contextMenu 让公告也具备 iOS 26 list 行的标准长按
                            // 体感:复制内容 / 置顶 / 删除(管理员)。
                            .contextMenu { announcementContextMenu(for: item) }
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
                                    // Haptic removed: 用户反馈辅助按钮过密震动
                                    Task { await viewModel.togglePin(item) }
                                } label: {
                                    Image(systemName: item.pinned ? "pin.slash" : "pin")
                                        .font(BsTypography.caption)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .help(item.pinned ? "取消置顶" : "置顶")
                                .accessibilityLabel(item.pinned ? "取消置顶" : "置顶")

                                Button(role: .destructive) {
                                    // Haptic removed: 仅打开 confirm dialog，非真删
                                    pendingDelete = item
                                } label: {
                                    Image(systemName: "trash")
                                        .font(BsTypography.caption)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("删除公告")
                                .buttonStyle(.borderless)
                                .accessibilityLabel("删除")
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
        .accessibilityLabel(item.profiles?.fullName ?? "用户")
        // Long-press v3:作者头像长按 → 半屏 profile sheet。
        .contextMenu {
            if let profile = item.profiles, let id = profile.id {
                Button {
                    profilePreview = UserPreviewData(
                        id: id,
                        fullName: profile.fullName,
                        avatarUrl: profile.avatarUrl
                    )
                } label: {
                    Label("查看资料", systemImage: "person.crop.square.filled.and.at.rectangle")
                }
            }
        }
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

    @ViewBuilder
    private func announcementContextMenu(for item: Announcement) -> some View {
        // 中部 mutation 优先 (longpress-system §菜单结构原则)
        Button {
            UIPasteboard.general.string = item.content
            Haptic.light()
        } label: {
            Label("复制内容", systemImage: "doc.on.doc")
        }

        Button {
            UIPasteboard.general.string = "\(item.title)\n\(item.content)"
            Haptic.light()
        } label: {
            Label("复制标题与内容", systemImage: "text.quote")
        }

        if canManage {
            Divider()

            Button {
                Task { await viewModel.togglePin(item) }
                Haptic.light()
            } label: {
                Label(item.pinned ? "取消置顶" : "置顶", systemImage: item.pinned ? "pin.slash" : "pin")
            }

            Divider()

            Button(role: .destructive) {
                // 不真删,等 confirmationDialog 二次确认 (hoisted state)
                Haptic.warning()
                pendingDelete = item
            } label: {
                Label("删除公告", systemImage: "trash")
            }
        }
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
