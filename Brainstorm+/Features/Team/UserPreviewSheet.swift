import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// UserPreviewSheet —— Avatar 长按弹窗 profile 预览
//
// Long-press v3 设计 (docs/longpress-system.md §v3):
//   头像长按 → 弹半屏 sheet,展示用户基本信息 + 3 个 quick actions:
//     • 发消息  → 打开 ChatRoomView (走 findOrCreateDirectChannel)
//     • 打电话  → tel:URL (仅 phone 非空)
//     • 查看资料 → push TeamMemberDetailView
//
// 设计参考:Slack iOS member sheet —— 大头像 + 姓名 + 角色 + 部门
// + 信息行,快捷动作横向排列。`.fraction(0.4) + .large` detents 让
// 用户既能瞥一眼也能展开看完整信息。
//
// 数据要求:`UserPreviewData` 是轻量 view-model,各 surface 用自己的
// model 现场拼装(approval ApprovalActorProfile / announcement
// AuthorProfile / team TeamMember / Profile 等)。**id 必填** —— 没 id
// 没法发消息或导航;avatar/role/dept/email/phone 全可选。
// ══════════════════════════════════════════════════════════════════

public struct UserPreviewData: Identifiable, Hashable {
    public let id: UUID
    public let fullName: String?
    public let avatarUrl: String?
    public let role: String?
    public let department: String?
    public let position: String?
    public let email: String?
    public let phone: String?

    public init(
        id: UUID,
        fullName: String? = nil,
        avatarUrl: String? = nil,
        role: String? = nil,
        department: String? = nil,
        position: String? = nil,
        email: String? = nil,
        phone: String? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.avatarUrl = avatarUrl
        self.role = role
        self.department = department
        self.position = position
        self.email = email
        self.phone = phone
    }
}

public struct UserPreviewSheet: View {
    let user: UserPreviewData
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionManager.self) private var sessionManager
    @State private var startingChat = false
    @State private var chatChannel: ChatChannel? = nil
    @State private var errorMessage: String? = nil
    @State private var pushDetail = false

    public init(user: UserPreviewData) {
        self.user = user
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BsSpacing.lg) {
                    avatarBlock
                        .padding(.top, BsSpacing.xl)

                    nameBlock

                    quickActionsRow
                        .padding(.top, BsSpacing.sm)

                    infoCard
                        .padding(.horizontal, BsSpacing.lg)

                    Spacer(minLength: BsSpacing.xl)
                }
                .frame(maxWidth: .infinity)
            }
            .background(BsColor.pageBackground.ignoresSafeArea())
            // Iter 6: 只读 profile preview 改成统一的 BsCloseButton X
            // (44pt 玻璃圆 = 系统 back button)。原来的"完成"文字按钮跟
            // 其他 sheet 不一致 → 收口到 bsModalNavBar。
            .bsModalNavBar(dismissBehavior: .auto)
            .navigationDestination(isPresented: $pushDetail) {
                TeamMemberDetailView(userId: user.id)
            }
            .navigationDestination(item: $chatChannel) { channel in
                ChatRoomView(viewModel: ChatRoomViewModel(client: supabase, channel: channel))
            }
            .zyErrorBanner($errorMessage)
        }
        .presentationDetents([.fraction(0.4), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Avatar block (大头像)

    @ViewBuilder
    private var avatarBlock: some View {
        ZStack {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.15))
                .overlay(
                    Circle()
                        .stroke(BsColor.brandAzure.opacity(0.25), lineWidth: 0.5)
                )
            if let urlString = user.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initials
                    }
                }
                .clipShape(Circle())
            } else {
                initials
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityLabel(user.fullName ?? "用户")
    }

    @ViewBuilder
    private var initials: some View {
        Text(initialString)
            .font(.custom("Outfit-Bold", size: 32))
            .foregroundStyle(BsColor.brandAzure)
    }

    private var initialString: String {
        if let name = user.fullName?.trimmingCharacters(in: .whitespaces),
           let first = name.first {
            return String(first)
        }
        return "?"
    }

    // MARK: - Name + role + dept

    @ViewBuilder
    private var nameBlock: some View {
        VStack(spacing: BsSpacing.xs) {
            Text(user.fullName?.isEmpty == false ? user.fullName! : "未命名")
                .font(BsTypography.brandTitle)
                .foregroundStyle(BsColor.ink)
                .multilineTextAlignment(.center)

            if let role = user.role, !role.isEmpty {
                Text(roleLabel(role))
                    .font(BsTypography.caption)
                    .padding(.horizontal, BsSpacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(BsColor.brandAzure.opacity(0.12)))
                    .foregroundStyle(BsColor.brandAzure)
            }
        }
    }

    // MARK: - Quick actions (3 横向圆按钮)

    @ViewBuilder
    private var quickActionsRow: some View {
        HStack(spacing: BsSpacing.lg) {
            quickAction(
                systemImage: "bubble.left.and.bubble.right.fill",
                label: "发消息",
                disabled: isSelf || startingChat
            ) {
                Haptic.light()
                Task { await startChat() }
            }

            if let phone = user.phone, !phone.isEmpty {
                quickAction(
                    systemImage: "phone.fill",
                    label: "打电话",
                    disabled: false
                ) {
                    Haptic.light()
                    if let url = URL(string: "tel://\(phone.filter { !$0.isWhitespace })") {
                        UIApplication.shared.open(url)
                    }
                }
            }

            quickAction(
                systemImage: "person.crop.square.filled.and.at.rectangle",
                label: "查看资料",
                disabled: false
            ) {
                Haptic.light()
                pushDetail = true
            }
        }
    }

    private func quickAction(
        systemImage: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: BsSpacing.xs + 2) {
                ZStack {
                    Circle()
                        .fill(BsColor.brandAzure.opacity(disabled ? 0.06 : 0.12))
                        .frame(width: 52, height: 52)
                    if startingChat && label == "发消息" {
                        ProgressView()
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(.title3, weight: .medium))
                            .foregroundStyle(disabled ? BsColor.inkFaint : BsColor.brandAzure)
                    }
                }
                Text(label)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(disabled ? BsColor.inkFaint : BsColor.ink)
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    // MARK: - Info card (部门 / 邮箱 / 电话 / 职位)

    @ViewBuilder
    private var infoCard: some View {
        let rows = infoRows
        if rows.isEmpty {
            EmptyView()
        } else {
            BsContentCard(padding: .none) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        infoRow(icon: row.icon, label: row.label, value: row.value, copyOnLongPress: row.copyable)
                        if idx < rows.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, BsSpacing.xs)
            }
        }
    }

    private struct InfoRowSpec {
        let icon: String
        let label: String
        let value: String
        let copyable: Bool
    }

    private var infoRows: [InfoRowSpec] {
        var rows: [InfoRowSpec] = []
        if let dept = user.department, !dept.isEmpty {
            rows.append(.init(icon: "building.2", label: "部门", value: dept, copyable: false))
        }
        if let pos = user.position, !pos.isEmpty {
            rows.append(.init(icon: "briefcase", label: "职位", value: pos, copyable: false))
        }
        if let email = user.email, !email.isEmpty {
            rows.append(.init(icon: "envelope", label: "邮箱", value: email, copyable: true))
        }
        if let phone = user.phone, !phone.isEmpty {
            rows.append(.init(icon: "phone", label: "电话", value: phone, copyable: true))
        }
        return rows
    }

    @ViewBuilder
    private func infoRow(icon: String, label: String, value: String, copyOnLongPress: Bool) -> some View {
        HStack(spacing: BsSpacing.md) {
            Image(systemName: icon)
                .font(BsTypography.caption)
                .foregroundStyle(BsColor.brandAzure)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
                Text(value)
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BsSpacing.md)
        .padding(.vertical, BsSpacing.sm + 2)
        .contentShape(Rectangle())
        .contextMenu {
            if copyOnLongPress {
                Button {
                    UIPasteboard.general.string = value
                    Haptic.success()
                } label: {
                    Label("复制\(label)", systemImage: "doc.on.doc")
                }
            }
        }
    }

    // MARK: - Helpers

    private var isSelf: Bool {
        user.id == sessionManager.currentProfile?.id
    }

    private func roleLabel(_ raw: String) -> String {
        let migrated = RBACManager.shared.migrateLegacyRole(raw).primaryRole
        switch migrated {
        case .superadmin: return "超级管理员"
        case .admin: return "管理员"
        case .employee: return "员工"
        }
    }

    /// Mirror 处理 TeamDirectoryView.startChat —— 复用 ChatListViewModel
    /// 的 findOrCreateDirectChannel + fetchChannel,推 ChatRoomView。
    @MainActor
    private func startChat() async {
        guard !isSelf else { return }
        startingChat = true
        defer { startingChat = false }
        let listVM = ChatListViewModel(client: supabase)
        do {
            let channelId = try await listVM.findOrCreateDirectChannel(with: user.id)
            let channel = try await listVM.fetchChannel(id: channelId)
            chatChannel = channel
        } catch {
            errorMessage = "无法开始聊天: \(ErrorLocalizer.localize(error))"
        }
    }
}
