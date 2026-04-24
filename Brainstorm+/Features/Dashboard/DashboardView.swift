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
    /// Phase 5：wordmark / "所有应用" tile 点击打开命令面板（.fullScreenCover）。
    @State private var showCommandPalette = false

    /// Phase 8：onboarding 结束后首次到达 Dashboard，wordmark 发 3 次脉冲
    /// 提示用户"这里可点"。一次性 @AppStorage 持久化。
    @AppStorage("bs_has_pulsed_wordmark") private var hasPulsedWordmark: Bool = false
    @State private var wordmarkPulse: Bool = false
    @State private var wordmarkPulseCount: Int = 0

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
                .fullScreenCover(isPresented: $showCommandPalette) {
                    BsCommandPalette()
                }
                .refreshable {
                    Haptic.soft()
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
                    showCommandPalette = true
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

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - NavBar items

    /// Leading: Logo + "BrainStorm+" wordmark（Outfit Bold 18pt per v1.1 §2.3）。
    /// 点击 = 打开命令面板。首次 onboarding 后 3 次脉冲发光环提示用户"这里可点"。
    private var wordmarkButton: some View {
        Button {
            Haptic.light()
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
            Haptic.light()
            showProfileSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(BsColor.brandAzure.opacity(0.12))
                Text(String(viewModel.profile?.fullName?.prefix(1) ?? "U"))
                    .font(Font.custom("Inter-SemiBold", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(BsColor.brandAzure)
            }
            .frame(width: 32, height: 32)
        }
        .accessibilityLabel("个人中心")
    }

    /// Trailing: 通知 bell，未读 Coral dot + 呼吸脉冲（尊重 Reduce Motion）
    private var notificationButton: some View {
        NavigationLink(destination: ActionItemHelper.destination(for: .notifications)) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(BsColor.ink)
                    .frame(width: 32, height: 32)

                // v1.2: Coral 未读 dot + 呼吸脉冲（opacity 0.65-1.0 周期 1.5s）
                // 目的：把 Coral 分布到 toolbar 持续可见位置，不是只靠"被点击才出现"
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    let t = CGFloat(ctx.date.timeIntervalSinceReferenceDate)
                    let pulse = reduceMotion ? 1.0 : (0.825 + 0.175 * sin(t * 4.2))
                    Circle()
                        .fill(BsColor.unreadBadge)
                        .frame(width: 7, height: 7)
                        .scaleEffect(reduceMotion ? 1.0 : (0.94 + 0.06 * sin(t * 4.2)))
                        .opacity(pulse)
                        .offset(x: -6, y: 6)
                }
            }
        }
        .accessibilityLabel("通知")
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Schedule section

    private var scheduleSectionHeader: some View {
        HStack(alignment: .bottom) {
            BsSectionTitle("今日班次", accent: .coral)
            Spacer()
            NavigationLink(destination: ScheduleView(isEmbedded: true)) {
                HStack(spacing: 2) {
                    Text("详情")
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2, weight: .semibold))
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

#Preview {
    DashboardView()
}
