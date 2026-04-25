import SwiftUI
import Supabase

// Parity target: `BrainStorm+-Web/src/app/dashboard/team/page.tsx`.
// PII-gated list: hr_ops or admin+ see email/phone + dept grouping;
// everyone else gets the flat card grid. Email is omitted on iOS
// because `profiles` doesn't store it (see VM note).
public struct TeamDirectoryView: View {
    @StateObject private var viewModel: TeamDirectoryViewModel
    @Environment(SessionManager.self) private var sessionManager

    // Phase 4.5 mirror: long-press 发消息 quick action pushes the same
    // ChatRoomView TeamMemberDetailView would have pushed. Local state so
    // the directory can bypass "tap-into-detail-first" for power users.
    @State private var chatDestination: ChatChannel? = nil
    @State private var startingChatFor: UUID? = nil
    @State private var chatError: String? = nil

    /// Bug-fix(滑动判定为点击 + 震动): NavigationLink in LazyVGrid inside ScrollView
    /// 在 iOS 26 触发太敏感 —— 手指放上去稍微停留就触发 tap (NavigationLink push +
    /// contextMenu preview haptic),用户想滑动反馈成"点击"。
    /// 改用 Button + .navigationDestination(item:) 的程序化导航:Button 在
    /// ScrollView 里有正确的 tap-vs-drag 判定 (drag 超过阈值会自动 cancel tap)。
    @State private var memberPushTarget: UUID? = nil

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 160), spacing: BsSpacing.md)
    ]

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    @MainActor
    public init(isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: TeamDirectoryViewModel())
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
        Group {
            if viewModel.isLoading && viewModel.allMembers.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
        .navigationTitle("团队")
        .navigationBarTitleDisplayMode(.large)
        // Bug-fix(滑动判定为点击 + 震动): 程序化导航 destination,配合 grid 内
        // Button + memberPushTarget binding,替代旧 NavigationLink(value:) 的
        // 过敏感 tap 触发。
        .navigationDestination(item: $memberPushTarget) { userId in
            TeamMemberDetailView(userId: userId)
        }
        .navigationDestination(item: $chatDestination) { channel in
            ChatRoomView(viewModel: ChatRoomViewModel(client: supabase, channel: channel))
        }
        .zyErrorBanner($chatError)
        .searchable(text: $viewModel.searchText,
                    prompt: viewModel.canViewDetails ? "搜索姓名、部门、职位…" : "搜索姓名、部门…")
        .task {
            await viewModel.load(sessionProfile: sessionManager.currentProfile)
        }
        .refreshable {
            await viewModel.load(sessionProfile: sessionManager.currentProfile)
        }
    }

    private func startChat(with memberId: UUID) async {
        startingChatFor = memberId
        defer { startingChatFor = nil }
        let listVM = ChatListViewModel(client: supabase)
        do {
            let channelId = try await listVM.findOrCreateDirectChannel(with: memberId)
            let channel = try await listVM.fetchChannel(id: channelId)
            chatDestination = channel
        } catch {
            chatError = "无法开始聊天: \(ErrorLocalizer.localize(error))"
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.lg) {
                header
                departmentChips
                memberBody
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.md)
        }
    }

    private var header: some View {
        HStack(spacing: BsSpacing.sm + 2) {
            Image(systemName: "person.3.fill")
                .font(.title3)
                .foregroundStyle(BsColor.brandAzure)
            VStack(alignment: .leading, spacing: 2) {
                Text("团队目录")
                    .font(BsTypography.sectionTitle)
                    .foregroundStyle(BsColor.ink)
                Text("查看公司成员信息 · 共 \(viewModel.filteredMembers.count) 人")
                    .font(BsTypography.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }
        }
    }

    private var departmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BsSpacing.sm) {
                chip(title: "全部部门", isSelected: viewModel.departmentFilter.isEmpty) {
                    viewModel.departmentFilter = ""
                }
                ForEach(viewModel.departments) { dept in
                    chip(title: dept.name, isSelected: viewModel.departmentFilter == dept.name) {
                        viewModel.departmentFilter = dept.name
                    }
                }
            }
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            // Haptic removed: 用户反馈 chip 切换过密震动
            action()
        } label: {
            Text(title)
                .font(BsTypography.caption)
                .padding(.horizontal, BsSpacing.md)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? BsColor.brandAzure.opacity(0.15) : BsColor.surfaceSecondary)
                )
                .foregroundStyle(isSelected ? BsColor.brandAzure : BsColor.ink)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var memberBody: some View {
        let rows = viewModel.filteredMembers
        if rows.isEmpty {
            BsEmptyState(
                title: "暂无成员",
                systemImage: "person.3",
                description: viewModel.searchText.isEmpty ? "没有找到团队成员数据" : "没有匹配的成员"
            )
            .frame(maxWidth: .infinity)
            .padding(.top, BsSpacing.xxxl)
        } else if viewModel.canViewDetails {
            groupedGrid
        } else {
            flatGrid(members: rows)
        }
    }

    private var groupedGrid: some View {
        VStack(alignment: .leading, spacing: BsSpacing.lg + 4) {
            ForEach(viewModel.groupedByDepartment, id: \.name) { group in
                VStack(alignment: .leading, spacing: BsSpacing.sm + 2) {
                    HStack(spacing: BsSpacing.xs + 2) {
                        Image(systemName: "building.2")
                            .font(BsTypography.caption)
                            .foregroundStyle(BsColor.brandAzure)
                        Text(group.name)
                            .font(BsTypography.cardSubtitle)
                            .foregroundStyle(BsColor.ink)
                        Text("· \(group.members.count) 人")
                            .font(BsTypography.caption)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    LazyVGrid(columns: gridColumns, spacing: BsSpacing.md) {
                        ForEach(Array(group.members.enumerated()), id: \.element.id) { index, m in
                            memberCard(m)
                                .bsAppearStagger(index: index)
                        }
                    }
                }
            }
        }
    }

    private func flatGrid(members: [TeamMember]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: BsSpacing.md) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, m in
                memberCard(m)
                    .bsAppearStagger(index: index)
            }
        }
    }

    private func memberCard(_ m: TeamMember) -> some View {
        // Bug-fix(滑动判定为点击 + 震动): 用 Button + memberPushTarget 替代
        // NavigationLink(value:)。Button 在 ScrollView/LazyVGrid 里正确
        // 处理 tap-vs-drag (drag 超过阈值会自动 cancel tap)。
        Button {
            memberPushTarget = m.id
        } label: {
            BsContentCard(padding: .medium) {
                VStack(alignment: .leading, spacing: BsSpacing.sm + 2) {
                    HStack(spacing: BsSpacing.sm + 2) {
                        avatar(for: m)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.fullName?.isEmpty == false ? m.fullName! : "未设置")
                                .font(BsTypography.cardSubtitle)
                                .lineLimit(1)
                                .foregroundStyle(BsColor.ink)
                            if let role = m.role, !role.isEmpty {
                                Text(roleLabel(role))
                                    .font(BsTypography.captionSmall)
                                    .padding(.horizontal, BsSpacing.xs + 2)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(BsColor.brandAzure.opacity(0.12)))
                                    .foregroundStyle(BsColor.brandAzure)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: BsSpacing.xs) {
                        if let dept = m.department, !dept.isEmpty {
                            infoRow(icon: "building.2", text: dept)
                        }
                        if let pos = m.position, !pos.isEmpty {
                            infoRow(icon: "briefcase", text: pos)
                        }
                        if viewModel.canViewDetails, let phone = m.phone, !phone.isEmpty {
                            infoRow(icon: "phone", text: phone)
                        }
                    }
                }
            }
            .bsInteractiveFeel(.card)
        }
        .buttonStyle(.plain)
        .bsContextMenu(memberContextMenu(m))
    }

    private func memberContextMenu(_ m: TeamMember) -> [BsContextMenuItem] {
        var items: [BsContextMenuItem] = []
        // Long-press → quick chat (mirrors Web team page "Message" affordance).
        // Skip when the row is the viewer themselves.
        if m.id != sessionManager.currentProfile?.id {
            items.append(BsContextMenuItem(
                label: "发消息",
                systemImage: "bubble.left.and.bubble.right",
                action: {
                    Task { await startChat(with: m.id) }
                }
            ))
        }
        if let phone = m.phone, !phone.isEmpty, viewModel.canViewDetails {
            items.append(BsContextMenuItem(
                label: "复制电话",
                systemImage: "phone.badge.plus",
                action: {
                    UIPasteboard.general.string = phone
                    Haptic.success()
                }
            ))
        }
        return items
    }

    private func avatar(for m: TeamMember) -> some View {
        Group {
            if let url = m.avatarUrl.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initialsAvatar(m.fullName)
                    }
                }
            } else {
                initialsAvatar(m.fullName)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private func initialsAvatar(_ name: String?) -> some View {
        let initials: String = {
            guard let n = name, !n.isEmpty else { return "?" }
            let first = n.first.map(String.init) ?? "?"
            return first
        }()
        return ZStack {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.18))
                .overlay(
                    Circle()
                        .stroke(BsColor.brandAzure.opacity(0.25), lineWidth: 0.5)
                )
            Text(initials)
                .font(BsTypography.cardSubtitle)
                .foregroundStyle(BsColor.brandAzure)
        }
        .accessibilityLabel(name ?? "用户")
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: BsSpacing.xs + 2) {
            Image(systemName: icon)
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 14)
            Text(text)
                .font(BsTypography.caption)
                .foregroundStyle(BsColor.inkMuted)
                .lineLimit(1)
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
