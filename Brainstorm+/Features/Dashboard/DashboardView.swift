import SwiftUI

// MARK: - Parity Backlog Placeholder

/// 用于 iOS 迁移中 Web 有但 iOS 未实现的模块，push 时显示占位页。
/// 被 ActionItemHelper 引用，保持 public。
public struct ParityBacklogDestination: View {
    public let moduleName: String
    public let webRoute: String

    public init(moduleName: String, webRoute: String = "") {
        self.moduleName = moduleName
        self.webRoute = webRoute
    }

    public var body: some View {
        ZStack {
            BsColor.pageBackground.ignoresSafeArea()
            VStack(spacing: BsSpacing.lg) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 60))
                    .foregroundStyle(BsColor.inkFaint)

                Text(moduleName)
                    .font(BsTypography.brandTitle)
                    .foregroundStyle(BsColor.ink)

                Text("Web 路由：\(webRoute.isEmpty ? "未知" : webRoute)")
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(BsColor.inkMuted)

                Text("该模块正在 iOS 迁移待办清单中，\n将在后续开发迭代中处理。")
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(BsColor.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BsSpacing.xxl + 8)
            }
        }
        .navigationTitle(moduleName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// ══════════════════════════════════════════════════════════════════
// DashboardView v2 —— Phase 4 widget-card Dashboard（v1.1）
//
// 设计来源：docs/plans/2026-04-24-ios-full-redesign-plan.md §三 + §五 Phase 4
//
// Widget Stack 从上到下：
//   1. AttendanceHeroCard  —— 签名 Liquid Glass + 液体 fill（Signature A）
//   2. BsWeeklyCadenceStrip—— 7 点本周打卡节奏（Signature C，裸 strip，不套卡）
//   3. BsAllAppsTile       —— "所有应用"启动卡（Signature B 辅入口；Phase 5 替换为命令面板）
//   4. roleBranchedSections—— 角色分支 KPI 卡（保留原 DashboardRoleSections 内容逻辑，材质后续 Phase 6 统一改 BsContentCard）
//   5. scheduleCardRow     —— 今日班次
//
// NavBar（§2.7 Dashboard 特殊）：
//   leading  = Logo 22pt + "BrainStorm+" Outfit Bold 18pt（v1.1 wordmark 升字号）
//             → 点击 = 打开 launcher/命令面板（Phase 4 临时 = BsAppLauncherSheet，Phase 5 = BsCommandPalette）
//   trailing = [Bell unread badge] [Avatar profile]
//   title display mode = .inline（wordmark 代替 Large Title）
//
// 已从旧版清除的内容（非遗漏）：
//   • attendanceStatusRow + stateAccent + punchRipple + attendanceNamespace
//     （200+ LOC，被 AttendanceHeroCard 整卡 primitive 取代）
//   • appsGridSection（dead code，Phase 25 v3 已挪入 BsAppLauncherSheet）
//   • backgroundLayer（未被调用）
//   • brandToolbarItem（合并进 leading wordmarkButton）
//   • launcherButton（合并进 wordmarkButton 点击）
//   • hasCap(_:) / isAdminTier（只服务 appsGridSection，一并删除）
// ══════════════════════════════════════════════════════════════════

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @StateObject private var widgets = DashboardWidgetsViewModel()
    @StateObject private var attendance = AttendanceViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showProfileSheet = false
    /// Phase 4 临时：wordmark / "所有应用" tile 点击打开 launcher sheet。
    /// Phase 5 替换为 BsCommandPalette 完整命令面板。
    @State private var showLauncher = false

    var body: some View {
        NavigationStack {
            mainList
                .scrollContentBackground(.hidden)
                .background(BsColor.pageBackground.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        wordmarkButton
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        notificationButton
                        avatarButton
                    }
                }
                .sheet(isPresented: $showProfileSheet) {
                    NavigationStack { SettingsView() }
                        .presentationDetents([.large])
                }
                .sheet(isPresented: $showLauncher) {
                    BsAppLauncherSheet()
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .refreshable {
                    Haptic.soft()
                    await viewModel.loadData()
                    await widgets.fetchAll(isManager: isManagerTier)
                    await attendance.loadToday()
                }
        }
        .task {
            await viewModel.loadData()
            await widgets.fetchAll(isManager: isManagerTier)
        }
    }

    // MARK: - Main widget stack

    @ViewBuilder
    private var mainList: some View {
        List {
            // —— 1. Attendance Hero（签名：液体 fill + 陀螺仪 tilt）——
            Section {
                AttendanceHeroCard(viewModel: attendance, isEmbedded: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: BsSpacing.sm, leading: BsSpacing.lg, bottom: BsSpacing.xs, trailing: BsSpacing.lg))
                    .listRowSeparator(.hidden)
            }

            // —— 2. Weekly Cadence strip（裸 strip，不套卡）——
            Section {
                BsWeeklyCadenceStrip(days: weekDays) { day in
                    // TODO(phase-4c): 长按 → 展示该日摘要 popover
                    Haptic.light()
                    _ = day
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: BsSpacing.xs, leading: BsSpacing.lg, bottom: BsSpacing.md, trailing: BsSpacing.lg))
                .listRowSeparator(.hidden)
            }

            // —— 3. 所有应用 启动卡 ——
            Section {
                BsAllAppsTile(previewIcons: BsAllAppsTile.sampleIcons) {
                    Haptic.light()
                    showLauncher = true
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: BsSpacing.xs, leading: BsSpacing.lg, bottom: BsSpacing.md, trailing: BsSpacing.lg))
                .listRowSeparator(.hidden)
            }

            // —— 4. 角色分支 KPI 卡（保留旧 DashboardRoleSections）——
            Section {
                roleBranchedSections
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: BsSpacing.sm, leading: BsSpacing.lg, bottom: BsSpacing.sm, trailing: BsSpacing.lg))
                    .listRowSeparator(.hidden)
            }

            // —— 5. 今日班次 ——
            Section {
                scheduleCardRow
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: BsSpacing.xs, leading: BsSpacing.lg, bottom: BsSpacing.xxl, trailing: BsSpacing.lg))
                    .listRowSeparator(.hidden)
            } header: {
                scheduleSectionHeader
                    .listRowInsets(EdgeInsets(top: BsSpacing.md, leading: BsSpacing.lg, bottom: BsSpacing.xs, trailing: BsSpacing.lg))
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
    }

    // MARK: - Weekly cadence data (stub v1)

    /// v1 占位实现：周内过去日用 attendance.today 是否有 clockOut 粗略推断（仅今日准确），
    /// 其他过去日暂无数据，一律显示为"未完成环"。
    /// TODO(phase-4c): 新增 AttendanceViewModel.loadThisWeek() 拉 7 天实际打卡记录填充。
    private var weekDays: [WeekDayCadence] {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        let weekday = cal.component(.weekday, from: today) // Sun=1 … Sat=7
        let mondayOffset = (weekday + 5) % 7                // Mon-based index 0…6
        let labels = ["一", "二", "三", "四", "五", "六", "日"]

        return (0..<7).map { idx in
            let isToday = idx == mondayOffset
            let isPast  = idx < mondayOffset
            // 仅今日可由 attendance.today 推断；过去日暂无数据
            let completed: Bool = {
                if isToday { return attendance.today?.clockOut != nil }
                return false
            }()
            return WeekDayCadence(
                id: "day-\(idx)",
                shortLabel: labels[idx],
                isCompleted: completed,
                isToday: isToday,
                isInFuture: idx > mondayOffset
            )
            .ignoringPast(isPast)
        }
    }

    // MARK: - NavBar items

    /// Leading: Logo + "BrainStorm+" wordmark（Outfit Bold 18pt per v1.1 §2.3）。
    /// 点击 = 打开 launcher / 命令面板（Phase 4 临时 sheet，Phase 5 替换为 palette）。
    private var wordmarkButton: some View {
        Button {
            Haptic.light()
            showLauncher = true
        } label: {
            HStack(spacing: 6) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text("BrainStorm+")
                    .font(BsTypography.brandWordmark)
                    .foregroundStyle(BsColor.ink)
                    .tracking(-0.2)
            }
        }
        .accessibilityLabel("BrainStorm+，点击打开应用面板")
    }

    /// Trailing: 头像入口，点击打开个人设置 sheet。
    private var avatarButton: some View {
        Button {
            Haptic.light()
            showProfileSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(BsColor.brandAzure.opacity(0.12))
                Text(String(viewModel.profile?.fullName?.prefix(1) ?? "U"))
                    .font(BsTypography.inter(14, weight: "SemiBold"))
                    .foregroundStyle(BsColor.brandAzure)
            }
            .frame(width: 32, height: 32)
        }
        .accessibilityLabel("个人中心")
    }

    /// Trailing: 通知 bell，未读红点（v1.1 errors 走 iOS 系统 .red）。
    private var notificationButton: some View {
        NavigationLink(destination: ActionItemHelper.destination(for: .notifications)) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BsColor.ink)
                    .frame(width: 32, height: 32)
                Circle()
                    .fill(Color.red)  // v1.1: 错误/紧急走 iOS .red
                    .frame(width: 7, height: 7)
                    .offset(x: -6, y: 6)
            }
        }
        .accessibilityLabel("通知")
    }

    // MARK: - Schedule section

    private var scheduleSectionHeader: some View {
        HStack {
            Text("今日班次")
                .font(BsTypography.label)
                .foregroundStyle(BsColor.inkMuted)
                .tracking(0.8)
                .textCase(.uppercase)
            Spacer()
            NavigationLink(destination: ScheduleView(isEmbedded: true)) {
                HStack(spacing: 2) {
                    Text("详情")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.brandAzure)
            }
        }
    }

    @ViewBuilder
    private var scheduleCardRow: some View {
        if viewModel.state == .loaded && viewModel.todayState == nil {
            scheduleEmptyRow
        } else {
            DayStateCardView(dws: viewModel.todayState, date: Date())
        }
    }

    private var scheduleEmptyRow: some View {
        HStack(spacing: BsSpacing.md) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(BsColor.brandAzure.opacity(0.6))
                .frame(width: 44, height: 44)
                .background(BsColor.brandAzure.opacity(0.06))
                .clipShape(Circle())
            Text("今日暂无排班")
                .font(BsTypography.bodyMedium)
                .foregroundStyle(BsColor.inkMuted)
            Spacer()
        }
        .padding(.horizontal, BsSpacing.lg)
        .padding(.vertical, BsSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Role-Branched Sections (unchanged content; 材质 Phase 6 统一改 BsContentCard)

    @ViewBuilder
    private var roleBranchedSections: some View {
        switch viewModel.dashboardTemplate {
        case .employee:
            EmployeeDashboardBody(viewModel: viewModel, widgets: widgets)
        case .admin:
            AdminDashboardBody(viewModel: viewModel, widgets: widgets)
        case .superadmin:
            SuperadminDashboardBody(viewModel: viewModel, widgets: widgets)
        }
    }

    private var isManagerTier: Bool {
        switch viewModel.dashboardTemplate {
        case .admin, .superadmin: return true
        case .employee: return false
        }
    }
}

// MARK: - WeekDayCadence helper —— 过去无数据的日子仍保持 isInFuture=false 但 isCompleted=false（空环）

private extension WeekDayCadence {
    /// 语义 no-op helper：标记过去无打卡数据 fallback。直接返回自身。
    /// 保留此扩展是为了以后换真实数据 pipeline 时有个锚点改写。
    func ignoringPast(_ isPast: Bool) -> WeekDayCadence { self }
}

#Preview {
    DashboardView()
}
