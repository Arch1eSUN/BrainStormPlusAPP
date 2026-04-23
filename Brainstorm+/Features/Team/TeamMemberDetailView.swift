import SwiftUI
import Supabase

public struct TeamMemberDetailView: View {
    @StateObject private var viewModel: TeamMemberDetailViewModel
    @Environment(SessionManager.self) private var sessionManager

    // Phase 4.5: team detail → 发起聊天 的目标 channel。一旦 "发起聊天" 按钮
    // 触发 RPC 拿到 channel，就把它塞进 `chatDestination`；
    // `.navigationDestination(item:)` 自动 push 进 ChatRoomView。
    @State private var chatDestination: ChatChannel? = nil
    @State private var startingChat: Bool = false
    @State private var chatError: String? = nil

    public init(userId: UUID) {
        _viewModel = StateObject(wrappedValue: TeamMemberDetailViewModel(userId: userId))
    }

    public var body: some View {
        Group {
            if viewModel.accessDenied {
                BsEmptyState(
                    title: "无权访问",
                    systemImage: "lock",
                    description: "你没有权限查看该成员的详细信息"
                )
            } else if viewModel.isLoading && viewModel.profile == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let profile = viewModel.profile {
                content(profile)
            } else {
                BsEmptyState(
                    title: "未找到成员",
                    systemImage: "person.slash",
                    description: viewModel.errorMessage ?? "无法加载该成员的资料"
                )
            }
        }
        .background(BsAmbientBackground())
        .navigationTitle("成员详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $chatDestination) { channel in
            ChatRoomView(viewModel: ChatRoomViewModel(client: supabase, channel: channel))
        }
        .zyErrorBanner($chatError)
        .task {
            await viewModel.load(sessionProfile: sessionManager.currentProfile)
        }
    }

    @ViewBuilder
    private func content(_ profile: Profile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.lg) {
                profileCard(profile)
                // Phase 4.5: 对齐 Web 成员详情页 "发起聊天" 按钮。
                // 自己的详情不显示（跟自己聊没意义）。
                if !viewModel.isSelf {
                    startChatButton
                }
                // TODO(team-detail-evaluation-panel): 已接入 TeamMemberEvaluationPanel
                // （AI 月度评分面板）。仅对 self / ai_evaluation_access / admin+ 开放。
                if canViewEvaluationPanel {
                    TeamMemberEvaluationPanel(profile: profile)
                }
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.md)
        }
    }

    /// 权限闸门：自己看自己 / 有 ai_evaluation_access 能力 / admin+ 可见
    private var canViewEvaluationPanel: Bool {
        if viewModel.isSelf { return true }
        if viewModel.viewerCapabilities.contains(.ai_evaluation_access) { return true }
        if viewModel.viewerPrimaryRole == .admin
            || viewModel.viewerPrimaryRole == .superadmin { return true }
        return false
    }

    // MARK: - Phase 4.5: 发起聊天

    private var startChatButton: some View {
        Button {
            Haptic.medium()
            Task { await startChatTapped() }
        } label: {
            HStack(spacing: BsSpacing.sm + 2) {
                if startingChat {
                    ProgressView()
                } else {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                }
                Text(startingChat ? "正在打开…" : "发起聊天")
            }
        }
        .buttonStyle(BsSecondaryButtonStyle())
        .disabled(startingChat)
    }

    /// Finds-or-creates a direct channel with this member and pushes
    /// `ChatRoomView`. Mirrors Web `findOrCreateDirectMessage` deep link
    /// `?dm=<userId>` flow in `dashboard/chat/page.tsx:155-166`.
    private func startChatTapped() async {
        guard let targetId = viewModel.profile?.id else { return }
        startingChat = true
        defer { startingChat = false }

        // Reuse the ChatListViewModel RPC helpers — single SupabaseClient
        // path, already has `findOrCreateDirectChannel` + `fetchChannel`.
        let listVM = ChatListViewModel(client: supabase)
        do {
            let channelId = try await listVM.findOrCreateDirectChannel(with: targetId)
            let channel = try await listVM.fetchChannel(id: channelId)
            chatDestination = channel
        } catch {
            chatError = "无法开始聊天: \(ErrorLocalizer.localize(error))"
        }
    }

    private func profileCard(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.lg) {
            HStack(alignment: .top, spacing: BsSpacing.md + 2) {
                avatar(for: profile)
                VStack(alignment: .leading, spacing: BsSpacing.xs) {
                    Text(profile.fullName?.isEmpty == false ? profile.fullName! : "未命名")
                        .font(BsTypography.sectionTitle)
                        .foregroundStyle(BsColor.ink)
                    if let role = profile.role, !role.isEmpty {
                        Text(roleLabel(role))
                            .font(BsTypography.bodySmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: BsSpacing.sm + 2) {
                if let dept = profile.department, !dept.isEmpty {
                    detailRow(icon: "building.2", label: "部门", value: dept)
                }
                if let position = profile.position, !position.isEmpty {
                    detailRow(icon: "briefcase", label: "职位", value: position)
                }
                if viewModel.canViewPII {
                    if let email = resolvedEmail(profile), !email.isEmpty {
                        detailRow(icon: "envelope", label: "邮箱", value: email)
                    }
                    if let phone = profile.phone, !phone.isEmpty {
                        detailRow(icon: "phone", label: "电话", value: phone)
                    }
                }
            }
        }
        .padding(BsSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bsGlassCard()
    }

    private func resolvedEmail(_ profile: Profile) -> String? {
        if viewModel.isSelf, let e = viewModel.selfEmail, !e.isEmpty { return e }
        if let e = profile.email, !e.isEmpty { return e }
        return nil
    }

    private func avatar(for profile: Profile) -> some View {
        let initials: String = {
            guard let n = profile.fullName, !n.isEmpty else { return "?" }
            return String(n.prefix(1))
        }()
        return Group {
            if let url = profile.avatarUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Circle().fill(BsColor.brandAzure.opacity(0.18))
                            Text(initials)
                                .font(BsTypography.brandTitle)
                                .foregroundStyle(BsColor.brandAzure)
                        }
                    }
                }
            } else {
                ZStack {
                    Circle().fill(BsColor.brandAzure.opacity(0.18))
                    Text(initials)
                        .font(BsTypography.brandTitle)
                        .foregroundStyle(BsColor.brandAzure)
                }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(BsColor.brandAzure.opacity(0.25), lineWidth: 0.5)
        )
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .center, spacing: BsSpacing.sm + 2) {
            Image(systemName: icon)
                .font(BsTypography.bodySmall)
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 18)
            Text(label)
                .font(BsTypography.bodySmall)
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(BsTypography.bodySmall)
                .foregroundStyle(BsColor.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func roleLabel(_ raw: String) -> String {
        let migrated = RBACManager.shared.migrateLegacyRole(raw).primaryRole
        switch migrated {
        case .superadmin: return "超级管理员"
        case .admin: return "管理员"
        case .employee: return "员工"
        }
    }
}
