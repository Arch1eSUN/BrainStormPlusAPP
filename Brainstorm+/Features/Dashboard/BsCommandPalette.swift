import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// BsCommandPalette —— v1.1「所有应用」命令面板
//
// 设计来源：docs/plans/2026-04-24-ios-full-redesign-plan.md §2.6 Signature B + §五 Phase 5
//
// 2 触发通道（v1.1 评审采纳，取消了下拉 70pt 通道）：
//   1. Dashboard NavBar wordmark 点击（主入口）
//   2. Dashboard "所有应用" 启动卡点击（辅入口，通过 BsAllAppsTile）
//
// 呈现方式：`.fullScreenCover(isPresented:)` + 内部 NavigationStack
//   • macOS Launchpad 式全屏覆盖，取代原 .sheet + .large detent
//   • Destination push 用 NavigationLink，借 palette 自己的 NavStack，
//     destination 全部以 isEmbedded: true 渲染（Phase 3 已参数化）
//   • iOS 原生左上 "< 面板" 返回按钮（NavigationStack 自动提供）
//   • 关闭 palette 用 toolbar 右上 × glass 圆按钮（.fullScreenCover 无 swipe-down）
//
// 功能特性：
//   • 4 分类 grid：常用 / 协作 / 业务 / 管理
//   • `.searchable` 原生搜索（模块名匹配）
//   • RBAC 过滤：adminOnly 门 + requires[Capability] 门 + superadmin 豁免
//   • Tile 为 4 列 LazyVGrid + 入场 stagger 动画（bsAppearStagger）
// ══════════════════════════════════════════════════════════════════

public struct BsCommandPalette: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery: String = ""
    /// Debounced search value — updated 180ms after user stops typing so
    /// filtering + stagger recompute don't thrash on every keystroke.
    @State private var debouncedQuery: String = ""

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
            .init(id: "admin_broadcast", name: "广播", systemImage: "dot.radiowaves.left.and.right", tint: BsColor.adminTint,
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
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
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
            .navigationTitle("所有应用")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索模块名称（如 考勤 / OKR / 审计）"
            )
            .onChange(of: searchQuery) { _, newValue in
                // Debounce: 180ms after last keystroke push into debouncedQuery.
                // Cheap enough for local in-memory filter, but avoids rebuilding
                // the grouped grid + re-running stagger animations per-char.
                Task { @MainActor in
                    let snapshot = newValue
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    if snapshot == searchQuery { debouncedQuery = snapshot }
                }
            }
        }
        // Bug-fix(右上 X 被椭圆容器包裹):
        // iOS 26 toolbar 在 .fullScreenCover + Liquid Glass 主题下会自动给
        // ToolbarItem 套一层 capsule glass 容器 → 即便我们显式画 Circle().fill,
        // 系统外层依旧 wrap 一个椭圆 → 视觉变成"圆 + 椭圆"叠加。
        // 修法:把 close 按钮从 toolbar 拿出来,改成顶级 ZStack overlay floating
        // button —— overlay 在 NavigationStack **外层**,不进 toolbar pipeline,
        // 系统也不再套 Liquid Glass capsule。alignment topTrailing 让它落在屏幕
        // 右上角 safe-area 内。
        .overlay(alignment: .topTrailing) {
            closeButtonOverlay
        }
        // Phase 25 v4：改用 NavigationLink push —— 完全 iOS 原生。
        // launcher 的 NavigationStack 自动加左上角 native 返回按钮，
        // 不覆盖 destination 自己的 Large Title。Tile 切换成 NavigationLink。
    }

    /// Floating close button —— 不走 toolbar 避免被 Liquid Glass capsule wrap。
    /// 视觉:32pt 内圈 Circle + 0.5pt border + 44pt hit area + ink xmark icon。
    private var closeButtonOverlay: some View {
        Button {
            // Haptic removed: 用户反馈关闭按钮过密震动
            dismiss()
        } label: {
            // 内层 32pt circle 是视觉本体;外层 44pt frame 扩 hit area 不影响视觉。
            ZStack {
                Circle()
                    .fill(BsColor.surfacePrimary)
                Circle()
                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
                Image(systemName: "xmark")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(BsColor.inkMuted)
            }
            .frame(width: 32, height: 32)
            .padding(6) // 32 + 6*2 = 44pt 总 hit area
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
        // 落点 = 系统 NavBar trailing 视觉位置:overlay 在 NavStack 外层,
        // alignment topTrailing 让 X 落在屏幕右上 safe-area 内。
        // padding 6pt top + 12pt trailing ≈ 系统 toolbar item insets。
        .padding(.top, 6)
        .padding(.trailing, BsSpacing.md)
    }

    // MARK: - Sections

    @ViewBuilder
    private func categorySection(category: ModuleCategory, items: [ModuleEntry], categoryIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            // Polish: unify section headers with BsSectionTitle so palette
            // picks up the Coral underline accent + uppercase tracking
            // shared across Dashboard/OKR/Reporting surfaces.
            BsSectionTitle(category.rawValue, accent: sectionAccent(for: category))
                .padding(.horizontal, BsSpacing.xs)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: BsSpacing.sm), count: 4),
                spacing: BsSpacing.lg
            ) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    // Batch 7 合并：palette 的 inline moduleTileButton 与 BsAppTile
                    // 视觉/签名完全一致（50x50 tint 方块 + SF palette icon +
                    // Inter-Medium 12pt 名）。复用 BsAppTile 后 palette 也顺带
                    // 拿到 drag-driven press scale + Haptic.light（比原版 TapGesture
                    // onEnded 更及时）。NavigationLink destination 由 BsAppTile
                    // 内部 wrap，行为不变。
                    BsAppTile(
                        name: item.name,
                        systemImage: item.systemImage,
                        tint: item.tint,
                        destination: item.destination
                    )
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

    /// Category → section accent mapping so each group has a distinct
    /// visual anchor (Coral for 常用/管理 admin-tier warmth, Mint for 协作,
    /// Azure for 业务).
    private func sectionAccent(for category: ModuleCategory) -> BsSectionAccent {
        switch category {
        case .daily:    return .coral
        case .collab:   return .mint
        case .business: return .azure
        case .admin:    return .coral
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        // Polish: reuse design-system ContentUnavailableView wrapper so the
        // palette's "no match" state matches every other list surface.
        let q = debouncedQuery.trimmingCharacters(in: .whitespaces)
        BsEmptyState(
            title: q.isEmpty ? "当前无可用应用" : "没有匹配“\(q)”的应用",
            systemImage: "sparkle.magnifyingglass",
            description: q.isEmpty
                ? "请联系管理员为你开通所需模块权限。"
                : "试试模块中文名（如 考勤 / 汇报 / OKR），或清空搜索后浏览全部分类。"
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, BsSpacing.xxl)
    }
}

