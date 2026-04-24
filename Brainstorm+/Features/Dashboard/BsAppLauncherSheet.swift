import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// BsAppLauncherSheet —— 「面板」功能启动台
//
// 架构修正（Bug 1 修复）：Dashboard sheet (NavStack) → Launcher 内再 NavStack
// push destination 会嵌套两层 NavStack，内层吞外层 back 按钮。
//
// 新架构：Launcher 是 sheet，tile 点击不 push —— 用 `.fullScreenCover(item:)`
// **覆盖呈现** destination。每个 destination View 自己带 NavStack 正常显示；
// 返回键由 destination 自己的 NavStack 负责；关闭时回到 launcher 保持打开，
// 用户可继续选下一个模块。
// ══════════════════════════════════════════════════════════════════

public struct BsAppLauncherSheet: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery: String = ""

    // MARK: - Module catalog

    private enum ModuleCategory: String, CaseIterable, Identifiable {
        case daily      = "常用"
        case collab     = "协作"
        case business   = "业务"
        case admin      = "管理"
        var id: String { rawValue }
    }

    /// 模块定义 —— Identifiable for fullScreenCover(item:)
    private struct ModuleEntry: Identifiable, Equatable {
        let id: String   // 用模块 name 做 id —— stable across rebuilds
        let name: String
        let systemImage: String
        let tint: Color
        let category: ModuleCategory
        let requires: [Capability]?
        let adminOnly: Bool
        let destination: () -> AnyView

        static func == (a: ModuleEntry, b: ModuleEntry) -> Bool { a.id == b.id }
    }

    private var allModules: [ModuleEntry] {
        [
            // —— 常用
            .init(id: "attendance", name: "考勤", systemImage: "clock.fill", tint: BsColor.brandAzure,
                  category: .daily, requires: nil, adminOnly: false,
                  destination: { AnyView(AttendanceView(isEmbedded: true)) }),
            .init(id: "schedule", name: "排班", systemImage: "calendar", tint: BsColor.brandAzure,
                  category: .daily, requires: nil, adminOnly: false,
                  destination: { AnyView(ScheduleView(isEmbedded: true)) }),
            .init(id: "leaves", name: "请假", systemImage: "calendar.badge.minus", tint: BsColor.brandMint,
                  category: .daily, requires: nil, adminOnly: false,
                  destination: { AnyView(LeavesView(client: supabase, isEmbedded: true)) }),
            .init(id: "reporting", name: "汇报", systemImage: "doc.text.fill", tint: BsColor.brandMint,
                  category: .daily, requires: nil, adminOnly: false,
                  destination: { AnyView(ReportingListView(viewModel: ReportingViewModel(client: supabase), isEmbedded: true)) }),
            .init(id: "notifications", name: "通知", systemImage: "bell.fill", tint: BsColor.brandCoral,
                  category: .daily, requires: nil, adminOnly: false,
                  destination: { AnyView(NotificationListView(viewModel: NotificationListViewModel(client: supabase), isEmbedded: true)) }),

            // —— 协作
            .init(id: "announcements", name: "公告", systemImage: "megaphone.fill", tint: BsColor.brandCoral,
                  category: .collab, requires: nil, adminOnly: false,
                  destination: { AnyView(AnnouncementsListView(viewModel: AnnouncementsListViewModel(client: supabase), isEmbedded: true)) }),
            .init(id: "team", name: "团队", systemImage: "person.3.fill", tint: BsColor.brandAzure,
                  category: .collab, requires: nil, adminOnly: false,
                  destination: { AnyView(TeamDirectoryView(isEmbedded: true)) }),
            .init(id: "activity", name: "活动", systemImage: "sparkle", tint: BsColor.brandMint,
                  category: .collab, requires: nil, adminOnly: false,
                  destination: { AnyView(ActivityFeedView(viewModel: ActivityFeedViewModel(client: supabase), isEmbedded: true)) }),
            .init(id: "knowledge", name: "知识库", systemImage: "book.fill", tint: BsColor.brandAzure,
                  category: .collab, requires: nil, adminOnly: false,
                  destination: { AnyView(KnowledgeListView(viewModel: KnowledgeListViewModel(client: supabase), isEmbedded: true)) }),

            // —— 业务
            .init(id: "projects", name: "项目", systemImage: "rectangle.3.group.fill", tint: BsColor.brandAzure,
                  category: .business, requires: nil, adminOnly: false,
                  destination: { AnyView(ProjectListView(viewModel: ProjectListViewModel(client: supabase), isEmbedded: true)) }),
            .init(id: "okr", name: "OKR", systemImage: "target", tint: BsColor.brandAzure,
                  category: .business, requires: nil, adminOnly: false,
                  destination: { AnyView(OKRListView(viewModel: OKRListViewModel(client: supabase), isEmbedded: true)) }),
            .init(id: "deliverables", name: "交付物", systemImage: "shippingbox.fill", tint: BsColor.brandMint,
                  category: .business, requires: nil, adminOnly: false,
                  destination: { AnyView(DeliverableListView(viewModel: DeliverableListViewModel(client: supabase), isEmbedded: true)) }),
            .init(id: "finance", name: "财务", systemImage: "yensign.circle.fill", tint: BsColor.brandCoral,
                  category: .business, requires: [.finance_ops], adminOnly: false,
                  destination: { AnyView(FinanceView(client: supabase, isEmbedded: true)) }),
            .init(id: "payroll", name: "薪资", systemImage: "banknote.fill", tint: BsColor.brandCoral,
                  category: .business, requires: [.finance_ops], adminOnly: false,
                  destination: { AnyView(PayrollListView(viewModel: PayrollListViewModel(client: supabase), isEmbedded: true)) }),
            .init(id: "hiring", name: "招聘", systemImage: "briefcase.fill", tint: BsColor.brandCoral,
                  category: .business, requires: [.hr_ops, .recruitment_approval], adminOnly: false,
                  destination: { AnyView(HiringCenterView(isEmbedded: true)) }),
            .init(id: "ai_analysis", name: "AI 分析", systemImage: "brain.head.profile", tint: BsColor.brandMint,
                  category: .business,
                  requires: [.ai_media_analysis, .ai_resume_screening, .ai_finance_docs, .ai_finance_reports],
                  adminOnly: false,
                  destination: { AnyView(AIAnalysisView(isEmbedded: true)) }),

            // —— 管理
            .init(id: "admin_center", name: "管理中心", systemImage: "shield.lefthalf.filled", tint: BsColor.brandAzure,
                  category: .admin, requires: nil, adminOnly: true,
                  destination: { AnyView(AdminCenterView(isEmbedded: true)) }),
            .init(id: "admin_users", name: "用户", systemImage: "person.crop.rectangle.stack.fill", tint: BsColor.brandAzure,
                  category: .admin, requires: nil, adminOnly: true,
                  destination: { AnyView(AdminUsersView(canAssignPrivileges: true, isEmbedded: true)) }),
            .init(id: "admin_audit", name: "审计", systemImage: "doc.text.magnifyingglass", tint: BsColor.inkMuted,
                  category: .admin, requires: nil, adminOnly: true,
                  destination: { AnyView(AdminAuditView(isEmbedded: true)) }),
            .init(id: "admin_broadcast", name: "广播", systemImage: "dot.radiowaves.left.and.right", tint: BsColor.brandCoral,
                  category: .admin, requires: nil, adminOnly: true,
                  destination: { AnyView(AdminBroadcastView(isEmbedded: true)) }),
            .init(id: "admin_org", name: "组织配置", systemImage: "building.2.fill", tint: BsColor.inkMuted,
                  category: .admin, requires: nil, adminOnly: true,
                  destination: { AnyView(AdminOrgConfigView(isEmbedded: true)) }),
            .init(id: "admin_holidays", name: "公休日历", systemImage: "calendar.badge.plus", tint: BsColor.brandMint,
                  category: .admin, requires: nil, adminOnly: true,
                  destination: { AnyView(AdminHolidaysView(isEmbedded: true)) }),
            // Phase 0b：新增全员考勤 admin 视图
            .init(id: "team_attendance", name: "全员考勤", systemImage: "person.3.sequence.fill", tint: BsColor.brandAzure,
                  category: .admin, requires: nil, adminOnly: true,
                  destination: { AnyView(TeamAttendanceView(isEmbedded: true)) }),
        ]
    }

    // MARK: - RBAC filter

    private var effectiveCaps: [Capability] {
        RBACManager.shared.getEffectiveCapabilities(for: sessionManager.currentProfile)
    }

    private var isAdminTier: Bool {
        let role = RBACManager.shared
            .migrateLegacyRole(sessionManager.currentProfile?.role)
            .primaryRole
        return role == .admin || role == .superadmin
    }

    private func isAccessible(_ m: ModuleEntry) -> Bool {
        if m.adminOnly && !isAdminTier { return false }
        if let req = m.requires, !req.isEmpty {
            let hasAny = req.contains { RBACManager.shared.hasCapability($0, in: effectiveCaps) }
            if !hasAny && !isAdminTier { return false }
        }
        return true
    }

    private var visibleModules: [ModuleEntry] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        return allModules.filter { m in
            guard isAccessible(m) else { return false }
            if q.isEmpty { return true }
            return m.name.localizedCaseInsensitiveContains(q)
        }
    }

    private var groupedModules: [(ModuleCategory, [ModuleEntry])] {
        ModuleCategory.allCases.compactMap { cat in
            let items = visibleModules.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    // MARK: - Body

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BsSpacing.xxl) {
                    if groupedModules.isEmpty {
                        emptyState
                            .padding(.top, BsSpacing.xxxl)
                    } else {
                        ForEach(Array(groupedModules.enumerated()), id: \.element.0) { catIdx, group in
                            categorySection(category: group.0, items: group.1, categoryIndex: catIdx)
                        }
                    }
                }
                .padding(.horizontal, BsSpacing.lg)
                .padding(.top, BsSpacing.md)
                .padding(.bottom, BsSpacing.xxxl)
            }
            .background(BsColor.pageBackground.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("面板")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索应用"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptic.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BsColor.ink)
                            .frame(width: 28, height: 28)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        // Phase 25 v4：改用 NavigationLink push —— 完全 iOS 原生。
        // launcher 的 NavigationStack 自动加左上角 native 返回按钮，
        // 不覆盖 destination 自己的 Large Title。Tile 切换成 NavigationLink。
    }

    // MARK: - Sections

    @ViewBuilder
    private func categorySection(category: ModuleCategory, items: [ModuleEntry], categoryIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            Text(category.rawValue)
                .font(.custom("Inter-SemiBold", size: 15))
                .foregroundStyle(BsColor.ink)
                .padding(.horizontal, BsSpacing.xs)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: BsSpacing.sm), count: 4),
                spacing: BsSpacing.lg
            ) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    moduleTileButton(item: item)
                        .bsAppearStagger(index: categoryIndex * 6 + idx, baseDelay: 0.03)
                }
            }
        }
        .padding(BsSpacing.lg)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    /// Tile —— NavigationLink 原生 push 到 destination。
    /// launcher 外层 NavStack 自动加 iOS 原生返回按钮。
    @ViewBuilder
    private func moduleTileButton(item: ModuleEntry) -> some View {
        NavigationLink {
            item.destination()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(item.tint.opacity(0.18))
                        .frame(width: 50, height: 50)

                    Image(systemName: item.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(item.tint, item.tint.opacity(0.55))
                        .frame(width: 50, height: 50)
                }
                Text(item.name)
                    .font(.custom("Inter-Medium", size: 12))
                    .foregroundStyle(BsColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Haptic.light() })
    }

    private var emptyState: some View {
        VStack(spacing: BsSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(BsColor.inkFaint)
            Text("没有匹配的应用")
                .font(BsTypography.cardTitle)
                .foregroundStyle(BsColor.ink)
            Text("试试别的关键词，或清空搜索")
                .font(BsTypography.bodySmall)
                .foregroundStyle(BsColor.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BsSpacing.xxxl)
    }
}

