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

// MARK: - Dashboard navigation destinations
//
// Bug-fix(返回 4 次回主页) — 真实 root cause:
//
// 之前 dashboard widget 卡（ApprovalSummaryCard / TeamMonitorCard /
// MyTasksSection / ActiveProjectsSection / RecentActivitySection 等）
// **全部** 渲染在 List 的 **同一个 Section row** 里：
//
//     Section { roleBranchedSections }   ← VStack of 5+ widgets in ONE row
//
// 每个 widget 内部又有 1~N 个 `BsCtaLink` (= `NavigationLink(destination:)`)
// + 内嵌的 row NavigationLink（TeamTodoAlertRow / ProjectRowCard / 各 contextMenu
// NavigationLink 项）。SwiftUI iOS 26 在 List row 含多个 NavigationLink
// 的场景下会把 row 整体 tap **链式触发所有 NavigationLink**, 4~5 个
// destination 一次性被 push 进 NavigationStack —— 用户体验就是 "点
// dashboard 任意位置 → 必须返回 4 次"，匹配 user 截图证据
// (Project → Task → Team → Approval pop chain)。
//
// 修法 (Phase 28 dashboard-nav-fix):
//   1. NavigationStack 接 `path: NavigationPath`，用 `.navigationDestination(for:)`
//      做 value-based 路由。AppModule + ProjectDetailDest 两个 hashable target。
//   2. 把 widget 的 NavigationLink 全部退役 → 改用 closure (`pushModule`/`pushProject`)
//      把目标 append 到 path。Button 触发 → SwiftUI 不再做隐式 row navigation 链触发。
//   3. `roleBranchedSections` 拆成多个 List Section，每个 widget 一个 Section row。
//      即便某个 widget 内部仍有多 button (TeamMonitorCard / ActiveProjectsSection)，
//      Section 边界让 SwiftUI 不把它们打包当成一个统一 row tap target。

/// Hashable wrapper used to push project detail with project id.
/// Separate type from AppModule because navigationDestination(for:) needs distinct types.
struct ProjectDetailDest: Hashable {
    let projectId: UUID
}

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @StateObject private var widgets = DashboardWidgetsViewModel()
    @StateObject private var attendance = AttendanceViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showProfileSheet = false
    /// Phase 5：wordmark / "所有应用" tile 点击打开命令面板（.fullScreenCover）。
    @State private var showCommandPalette = false

    /// Phase 28: programmatic NavigationStack path —— 把所有 dashboard push 都
    /// 走 value-based 路由,杜绝 List-row 链式 NavigationLink 触发。
    @State private var navPath: NavigationPath = NavigationPath()

    /// Phase 8：onboarding 结束后首次到达 Dashboard，wordmark 发 3 次脉冲
    /// 提示用户"这里可点"。一次性 @AppStorage 持久化。
    @AppStorage("bs_has_pulsed_wordmark") private var hasPulsedWordmark: Bool = false
    @State private var wordmarkPulse: Bool = false
    @State private var wordmarkPulseCount: Int = 0

    /// Phase 4c：长按 week strip 某日 → 展示该日摘要 sheet。
    /// 用 optional DayPeekData 作 `.sheet(item:)` 触发源（非 nil 即显示）。
    @State private var dayPeek: DayPeekSheetItem?

    var body: some View {
        NavigationStack(path: $navPath) {
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
                .navigationDestination(for: AppModule.self) { module in
                    ActionItemHelper.destination(for: module)
                }
                .navigationDestination(for: ProjectDetailDest.self) { dest in
                    ProjectDetailView(
                        viewModel: ProjectDetailViewModel(client: supabase, projectId: dest.projectId)
                    )
                }
                .sheet(isPresented: $showProfileSheet) {
                    NavigationStack { SettingsView() }
                        .presentationDetents([.large])
                }
                .sheet(item: $dayPeek) { item in
                    DayPeekSheet(data: item.data)
                }
                .fullScreenCover(isPresented: $showCommandPalette) {
                    BsCommandPalette()
                }
                .refreshable {
                    // Haptic removed: 用户反馈滑动场景不应震动
                    await viewModel.loadData()
                    await widgets.fetchAll(isManager: isManagerTier)
                    await attendance.loadToday()
                    await attendance.loadThisWeek()
                }
        }
        .task {
            await viewModel.loadData()
            await widgets.fetchAll(isManager: isManagerTier)
            await attendance.loadThisWeek()
        }
    }

    // MARK: - Programmatic navigation helpers
    //
    // 这两个 closure 通过参数下传到 employeeWidgetSections / adminWidgetSections /
    // superadminWidgetSections 里每个 widget 卡。widget 内部不再用 NavigationLink，
    // 改用 Button { pushModule(.tasks) } —— 干净的单一 tap target。

    private func pushModule(_ module: AppModule) {
        navPath.append(module)
    }

    private func pushProject(_ projectId: UUID) {
        navPath.append(ProjectDetailDest(projectId: projectId))
    }

    // MARK: - Main widget stack

    @ViewBuilder
    private var mainList: some View {
        List {
            // —— 1. Attendance Hero（签名：液体 fill + 陀螺仪 tilt）——
            Section {
                // v1.3: todayState 决定 overtime 阈值 —— 弹性按 8h 算，
                // 部门固定班次按 expectedStart/End 差值
                AttendanceHeroCard(
                    viewModel: attendance,
                    isEmbedded: true,
                    todayState: viewModel.todayState
                )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: BsSpacing.sm, leading: BsSpacing.lg, bottom: BsSpacing.xs, trailing: BsSpacing.lg))
                    .listRowSeparator(.hidden)
            }

            // —— 2. Weekly Cadence strip（裸 strip，不套卡）——
            Section {
                BsWeeklyCadenceStrip(days: weekDays) { day in
                    // Phase 4c 已接入：长按 → 展示该日摘要 sheet
                    // Haptic removed: BsWeeklyCadenceStrip 内部已含按压 haptic，避免双重震动
                    dayPeek = makeDayPeek(for: day)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: BsSpacing.xs, leading: BsSpacing.lg, bottom: BsSpacing.md, trailing: BsSpacing.lg))
                .listRowSeparator(.hidden)
            }

            // —— 3. 所有应用 启动卡 ——
            Section {
                BsAllAppsTile(previewIcons: BsAllAppsTile.sampleIcons) {
                    // Haptic removed: BsAllAppsTile 内部已含按压 haptic，避免双重震动
                    showCommandPalette = true
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: BsSpacing.xs, leading: BsSpacing.lg, bottom: BsSpacing.md, trailing: BsSpacing.lg))
                .listRowSeparator(.hidden)
            }

            // —— 4. 角色分支 KPI 卡 ——
            // Bug-fix(返回 4 次回主页): roleBranchedSections 不再包成单一 Section row。
            // 让每个 widget 自己占一个 Section row,Section 边界 = SwiftUI tap-target 边界,
            // 杜绝 row 内多 NavigationLink 链式触发。详见 DashboardDestination 注释。
            roleBranchedSectionRows

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

    /// Phase 4c: 从 AttendanceViewModel.thisWeek 拉真实一周打卡记录（Supabase 共享表）。
    /// 完成判定：该日有 clockOut → 完整完成（绿点）；仅 clockIn 无 clockOut → 不算完成；
    /// 今日可以只 clockIn 未 clockOut 的情况显示为"进行中"（也算本日 cadence 上有一点）。
    private var weekDays: [WeekDayCadence] {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        let weekday = cal.component(.weekday, from: today) // Sun=1 … Sat=7
        let mondayOffset = (weekday + 5) % 7                // Mon-based index 0…6
        let labels = ["一", "二", "三", "四", "五", "六", "日"]

        return (0..<7).map { idx in
            let isToday = idx == mondayOffset
            let dayDiff = idx - mondayOffset
            let date = cal.date(byAdding: .day, value: dayDiff, to: today) ?? today
            let iso = Self.isoDate(date)
            let record = attendance.thisWeek[iso]

            // 完成语义：过去日 clockOut 存在 = 完成；今日 clockIn 存在 = 算"标记"
            let completed: Bool = {
                if isToday {
                    return record?.clockIn != nil
                }
                return record?.clockOut != nil
            }()

            return WeekDayCadence(
                id: iso,
                shortLabel: labels[idx],
                isCompleted: completed,
                isToday: isToday,
                isInFuture: idx > mondayOffset
            )
        }
    }

    /// 共享 ISO 日期 formatter（避免每次调用都 alloc）
    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func isoDate(_ date: Date) -> String {
        isoDayFormatter.string(from: date)
    }

    // MARK: - Day peek (long-press on week strip)

    /// 把 `WeekDayCadence` + 本周 attendance map 装成 sheet 可渲染的 `DayPeekData`。
    /// 从 `attendance.thisWeek[iso]` 查该日打卡行；Date 从 iso 反解回来，
    /// 避免再算一遍 Monday offset。反解失败 → 退回 Date() 兜底（显示"无数据"）。
    private func makeDayPeek(for day: WeekDayCadence) -> DayPeekSheetItem {
        let date = Self.isoDayFormatter.date(from: day.id) ?? Date()
        let record = attendance.thisWeek[day.id]
        return DayPeekSheetItem(
            data: DayPeekData(
                date: date,
                iso: day.id,
                attendance: record,
                isInFuture: day.isInFuture
            )
        )
    }

    // MARK: - NavBar items

    /// Leading: Logo + "BrainStorm+" wordmark（Outfit Bold 18pt per v1.1 §2.3）。
    /// 点击 = 打开命令面板。首次 onboarding 后 3 次脉冲发光环提示用户"这里可点"。
    private var wordmarkButton: some View {
        Button {
            // Haptic removed: 用户反馈 navbar 按钮过密震动
            // 任何一次手动点击都停止 pulse 提示，算任务达成
            if !hasPulsedWordmark { hasPulsedWordmark = true }
            showCommandPalette = true
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
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                // Phase 8: onboarding 后 3 次 azure 脉冲发光环
                // 未 pulse 过：从 0 opacity 涨到 0.55，repeat 3 次后停
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(BsColor.brandAzure, lineWidth: 2)
                    .opacity(wordmarkPulse ? 0.0 : 0.55)
                    .scaleEffect(wordmarkPulse ? 1.3 : 1.0)
                    .allowsHitTesting(false)
                    .opacity(hasPulsedWordmark ? 0 : 1)
            )
        }
        .accessibilityLabel("BrainStorm+，点击打开应用面板")
        .onAppear {
            guard !hasPulsedWordmark else { return }
            // 脉冲 3 次后持久化，避免每次回到 Dashboard 都闪
            wordmarkPulseCount = 0
            runPulseLoop()
        }
    }

    /// 脉冲循环：1s 一次 scale+fade，共 3 次
    private func runPulseLoop() {
        withAnimation(.easeOut(duration: 1.0)) {
            wordmarkPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            wordmarkPulse = false
            wordmarkPulseCount += 1
            if wordmarkPulseCount < 3 && !hasPulsedWordmark {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    runPulseLoop()
                }
            } else {
                hasPulsedWordmark = true
            }
        }
    }

    /// Trailing: 头像入口，点击打开个人设置 sheet。
    private var avatarButton: some View {
        Button {
            // Haptic removed: 用户反馈 avatar 按钮过密震动
            showProfileSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(BsColor.brandAzure.opacity(0.12))
                // Bug-fix: 不显示 "U" 占位字符。profile 未到货前只留 halo，
                // 到货后才渲染姓名首字母，避免顶部 avatar flash "U" → 真名。
                if let initial = viewModel.profile?.fullName?.prefix(1), !initial.isEmpty {
                    Text(String(initial))
                        .font(Font.custom("Inter-SemiBold", size: 14, relativeTo: .subheadline))
                        .foregroundStyle(BsColor.brandAzure)
                        .transition(.opacity)
                }
            }
            .frame(width: 32, height: 32)
            .animation(BsMotion.Anim.smooth, value: viewModel.profile?.fullName)
        }
        .accessibilityLabel("个人中心")
    }

    /// Trailing: 通知 bell，未读 Coral dot + 呼吸脉冲（尊重 Reduce Motion）
    ///
    /// v1.3.1 perf：原版用 `TimelineView(.animation(1/30))` 每秒重建 30 次 dot
    /// 并在 body 里算 `sin()` —— 这个 view 在整个 app 生命周期内常驻 NavBar，
    /// CPU 从未归 0。改为 `withAnimation.repeatForever` 一次性声明 → SwiftUI
    /// 走 Core Animation 插值（GPU），主线程无负担。
    ///
    /// Phase 28: NavigationLink → Button + path append, 跟 dashboard 其他 push
    /// 一致走 value-based 路由。
    private var notificationButton: some View {
        Button {
            pushModule(.notifications)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(BsColor.ink)
                    .frame(width: 32, height: 32)

                // Coral 未读 dot + 呼吸脉冲（opacity 0.65→1.0，周期 1.5s）
                // 目的：把 Coral 分布到 toolbar 持续可见位置，不只靠"被点击才出现"
                Circle()
                    .fill(BsColor.unreadBadge)
                    .frame(width: 7, height: 7)
                    .scaleEffect(reduceMotion ? 1.0 : (bellPulseActive ? 1.0 : 0.88))
                    .opacity(reduceMotion ? 1.0 : (bellPulseActive ? 1.0 : 0.65))
                    .offset(x: -6, y: 6)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                            bellPulseActive = true
                        }
                    }
            }
        }
        .accessibilityLabel("通知")
    }

    /// Bell dot 呼吸脉冲的布尔锚点；withAnimation 绑定此值后 SwiftUI
    /// 自动在两端点反复 tween，不需要 TimelineView 每帧重建 view。
    @State private var bellPulseActive: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Schedule section

    private var scheduleSectionHeader: some View {
        HStack(alignment: .bottom) {
            BsSectionTitle("今日班次", accent: .coral)
            Spacer()
            // Phase 28: NavigationLink → Button programmatic push,跟 dashboard 其他链路保持一致。
            Button {
                pushModule(.schedules)
            } label: {
                HStack(spacing: 2) {
                    Text("详情")
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2, weight: .semibold))
                }
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.brandAzure)
            }
            .buttonStyle(.plain)
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
                .font(.system(.title3, weight: .light))
                .foregroundStyle(BsColor.brandAzure.opacity(0.6))
                .frame(width: 44, height: 44)
                .background(BsColor.brandAzure.opacity(0.06))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("今日暂无排班")
                    .font(BsTypography.bodyMedium)
                    .foregroundStyle(BsColor.ink)
                Text("休息日 · 下拉可刷新最新班表")
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer(minLength: 0)
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

    // MARK: - Role-Branched Section Rows
    //
    // Phase 28: 每个 widget 占一个独立 List Section row,确保 SwiftUI 不会
    // 把"整组 widget"当成一个 row tap target。每个 widget 内部 navigation
    // 改用 closure 回调到 dashboard 的 navPath。

    @ViewBuilder
    private var roleBranchedSectionRows: some View {
        switch viewModel.dashboardTemplate {
        case .employee:
            employeeWidgetSections
        case .admin:
            adminWidgetSections
        case .superadmin:
            superadminWidgetSections
        }
    }

    /// 单 widget 的 listRow 修饰：clear bg + 16pt 水平边 + 8pt 垂直气口 + 隐藏分隔。
    /// 用 ViewModifier 封装,避免每个 Section 内重复一长串 listRowInsets。
    private func widgetRowDecor<V: View>(_ view: V) -> some View {
        view
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: BsSpacing.sm, leading: BsSpacing.lg, bottom: BsSpacing.sm, trailing: BsSpacing.lg))
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var employeeWidgetSections: some View {
        Section { widgetRowDecor(MyTasksSection(tasks: widgets.myTasks, pushModule: pushModule)) }
        Section { widgetRowDecor(MonthlySnapshotSection(snapshot: widgets.monthlySnapshot)) }
        Section {
            widgetRowDecor(
                ActiveProjectsSection(
                    projects: widgets.activeProjects,
                    pushModule: pushModule,
                    pushProject: pushProject
                )
            )
        }
        Section { widgetRowDecor(MyOkrSection(objectives: widgets.myOkr, pushModule: pushModule)) }
        Section { widgetRowDecor(RecentActivitySection(activity: widgets.recentActivity)) }
    }

    @ViewBuilder
    private var adminWidgetSections: some View {
        Section {
            widgetRowDecor(
                HStack(spacing: BsSpacing.md) {
                    ApprovalSummaryCard(pending: widgets.pendingApprovals, pushModule: pushModule)
                    RiskOverviewCard(risk: widgets.riskOverview)
                }
            )
        }
        Section {
            widgetRowDecor(
                TeamMonitorCard(stats: widgets.teamStats, alerts: widgets.teamTodoAlerts, pushModule: pushModule)
            )
        }
        Section { widgetRowDecor(MyTasksSection(tasks: widgets.myTasks, pushModule: pushModule)) }
        Section { widgetRowDecor(MonthlySnapshotSection(snapshot: widgets.monthlySnapshot)) }
        Section {
            widgetRowDecor(
                ActiveProjectsSection(
                    projects: widgets.activeProjects,
                    pushModule: pushModule,
                    pushProject: pushProject
                )
            )
        }
        Section { widgetRowDecor(RecentActivitySection(activity: widgets.recentActivity)) }
    }

    @ViewBuilder
    private var superadminWidgetSections: some View {
        Section { widgetRowDecor(ExecutiveKPIsCard(kpis: widgets.executiveKpis)) }
        Section {
            widgetRowDecor(
                HStack(spacing: BsSpacing.md) {
                    ApprovalSummaryCard(pending: widgets.pendingApprovals, pushModule: pushModule)
                    RiskOverviewCard(risk: widgets.riskOverview)
                }
            )
        }
        Section {
            widgetRowDecor(
                TeamMonitorCard(stats: widgets.teamStats, alerts: widgets.teamTodoAlerts, pushModule: pushModule)
            )
        }
        Section { widgetRowDecor(MyTasksSection(tasks: widgets.myTasks, pushModule: pushModule)) }
        Section { widgetRowDecor(MonthlySnapshotSection(snapshot: widgets.monthlySnapshot)) }
        Section {
            widgetRowDecor(
                ActiveProjectsSection(
                    projects: widgets.activeProjects,
                    pushModule: pushModule,
                    pushProject: pushProject
                )
            )
        }
        Section { widgetRowDecor(RecentActivitySection(activity: widgets.recentActivity)) }
    }

    private var isManagerTier: Bool {
        switch viewModel.dashboardTemplate {
        case .admin, .superadmin: return true
        case .employee: return false
        }
    }
}

// MARK: - Day peek identifiable wrapper

/// `.sheet(item:)` 需要 Identifiable —— 用 iso 字符串作 id 保证同日重复长按
/// 不会触发重挂载。
struct DayPeekSheetItem: Identifiable {
    let data: DayPeekData
    var id: String { data.iso }
}

#Preview {
    DashboardView()
}
