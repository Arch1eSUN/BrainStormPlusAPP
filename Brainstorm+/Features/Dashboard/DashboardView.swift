import SwiftUI

// MARK: - Parity Backlog Placeholder
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
// DashboardView — iOS 原生首屏 (Phase 11.1 重写)
//
// 关键变化 vs. 旧版:
//   • 去掉 .navigationBarHidden(true) → iOS 原生 NavigationBar 接管
//   • 去掉手搓 headerSection → toolbar leading 头像 + trailing 通知
//   • 去掉 Web hero 大卡 → 第一行原生"已签到"Liquid Glass row
//   • ScrollView+VStack → List(.plain) + Section (原生 List,blob 透过 .scrollContentBackground(.hidden))
//   • navigationTitle = 动态时间问候("早上好,Archie" 像 Apple Fitness)
//   • .navigationBarTitleDisplayMode(.large) 开 iOS Large Title + 下拉 blur
//   • .refreshable + Haptic.soft 原生 pull-to-refresh
// ══════════════════════════════════════════════════════════════════

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @StateObject private var widgets = DashboardWidgetsViewModel()
    @StateObject private var attendance = AttendanceViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showProfileSheet = false

    /// Phase 21：流体 namespace —— 给状态胶囊 + CTA 挂 glassEffectID，
    /// 跨 clockState 变化时玻璃自动 morph 而不是切换（Liquid Glass 签名行为）。
    @Namespace private var attendanceNamespace

    /// Phase 24：打卡成功 ripple —— punch 成功后该值递增，progress ring 内
    /// 叠加一层从中心向外扩散的品牌色环，0.8s 自行消散。
    @State private var punchRipple: Int = 0

    /// Phase 25：「面板」启动台 sheet 开关
    @State private var showLauncher = false

    var body: some View {
        NavigationStack {
            mainList
                .scrollContentBackground(.hidden)
                .background(BsColor.pageBackground.ignoresSafeArea())  // 纯净系统灰，无弥散
                .navigationTitle(greetingTitle)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        avatarButton
                    }
                    ToolbarItem(placement: .principal) {
                        brandToolbarItem
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        launcherButton
                        notificationButton
                    }
                }
                .sheet(isPresented: $showProfileSheet) {
                    NavigationStack { SettingsView() }
                        .presentationDetents([.large])
                }
                // Phase 25 v3：「面板」启动台 sheet
                .sheet(isPresented: $showLauncher) {
                    BsAppLauncherSheet()
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .refreshable {
                    Haptic.soft()
                    await viewModel.loadData()
                    await widgets.fetchAll(isManager: isManagerTier)
                }
        }
        .task {
            await viewModel.loadData()
            await widgets.fetchAll(isManager: isManagerTier)
        }
    }

    // MARK: - Greeting Title (iOS 原生 Large Title)

    /// Phase 20：恢复原生 Large Title，拼完整 "问候 + 名字"。名字回 Ink 不再渐变。
    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case 5..<11:  greeting = "早上好"
        case 11..<13: greeting = "中午好"
        case 13..<18: greeting = "下午好"
        case 18..<23: greeting = "晚上好"
        default:      greeting = "夜深了"
        }
        let name = viewModel.profile?.fullName ?? ""
        return name.isEmpty ? greeting : "\(greeting)，\(name)"
    }

    /// 品牌条右侧副信息 —— 日期 + 角色（或缺省日期）
    private var brandStripSubtitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: Date())
    }

    // MARK: - Main List

    @ViewBuilder
    private var mainList: some View {
        // Phase 21：GlassEffectContainer 让 Dashboard 所有 .glassEffect 元素
        // （玻璃卡 / 胶囊 / CTA 按钮）在靠近时**可以融合**、远离时**拉开**——
        // iOS 26 Liquid Glass 签名物理行为
        GlassEffectContainer(spacing: 16) {
            List {
                // Section 1 — 今日状态 Liquid Glass row (不挂 Section header)
                //
                // 弥散彻底退出 —— Phase 22：纯流体 committed。BsTimeHero 已删。
                //
                // Phase 25：Dashboard 升级为"工作台" —— 飞书/钉钉 pattern
                // Attendance hero 保留 → 应用网格 → 角色 widget 折叠区 → 今日班次

                Section {
                    attendanceStatusRow
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: BsSpacing.lg, bottom: 4, trailing: BsSpacing.lg))
                        .listRowSeparator(.hidden)
                }

                // Phase 25 v3：apps grid 挪到「面板」sheet 里。Dashboard 彻底解放纯信息展示。
                // 入口在 NavBar toolbar —— grid icon 点击打开 launcher。

                // Section 2 — role-branched KPI 展示
                Section {
                    roleBranchedSections
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: BsSpacing.sm, leading: BsSpacing.lg, bottom: BsSpacing.sm, trailing: BsSpacing.lg))
                        .listRowSeparator(.hidden)
                }

                // Section 3 — 今日班次 (Schedule)
                Section {
                    scheduleCardRow
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: BsSpacing.lg, bottom: BsSpacing.xl, trailing: BsSpacing.lg))
                        .listRowSeparator(.hidden)
                } header: {
                    scheduleSectionHeader
                        .listRowInsets(EdgeInsets(top: BsSpacing.md, leading: BsSpacing.lg, bottom: BsSpacing.xs, trailing: BsSpacing.lg))
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    // MARK: - Attendance quick-clock widget (Fusion: 弥散 + 流体 + Linear)
    //
    // 重构目标: 招牌 Dashboard hero card, 替代老 3-列时间网格 + 实色按钮布局。
    //   • 弥散 — 卡内 RadialGradient 按状态渲染环境氛围 (topLeading tint)
    //   • 流体 — 状态胶囊 + CTA 按钮都走 iOS 26 `.glassEffect(.regular.tint(...))`
    //   • Linear 编辑态度 — Inter sentence case header,英雄 Progress Ring 居中,
    //     右侧两行 label+time 极简副栏,无 3 等分视觉平均
    //
    // 整卡仍可点进 AttendanceView,按钮区拦截自身 tap (NavigationLink ZStack 技巧)

    /// 按状态切换的主色调 —— 驱动 ambient gradient、status pill、progress ring、CTA。
    private var stateAccent: Color {
        switch attendance.clockState {
        case .ready:     return BsColor.brandMint
        case .clockedIn: return BsColor.brandAzure
        case .done:      return BsColor.success
        }
    }

    private var statusCapsuleText: String {
        switch attendance.clockState {
        case .ready:     return "未打卡"
        case .clockedIn: return "已打卡"
        case .done:      return "已完成"
        }
    }

    private var statusCapsuleIcon: String {
        switch attendance.clockState {
        case .ready:     return "clock"
        case .clockedIn: return "clock.fill"
        case .done:      return "checkmark.seal.fill"
        }
    }

    /// 完整中文日期副标题: "4月23日 周四"
    private var formattedFullDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: Date())
    }

    /// 给 ProgressRing 的当前日进度: 以 8h 标准工时为分母。
    /// - .ready → 0
    /// - .clockedIn → (now - clockIn) / 8h,clamp [0,1]
    /// - .done → (clockOut - clockIn) / 8h,clamp [0,1]
    private func dayProgress(at reference: Date) -> Double {
        guard let clockIn = attendance.today?.clockIn else { return 0 }
        let end: Date
        switch attendance.clockState {
        case .ready:
            return 0
        case .clockedIn:
            end = reference
        case .done:
            end = attendance.today?.clockOut ?? reference
        }
        let interval = end.timeIntervalSince(clockIn)
        guard interval > 0 else { return 0 }
        let p = interval / (8 * 3600)
        return min(max(p, 0), 1)
    }

    private var attendanceStatusRow: some View {
        ZStack {
            // 背板导航链接 —— 整卡可点进 AttendanceView 看历史详情。
            // 放在 ZStack 底层,CTA 按钮盖在上面独立拦截点击。
            // Phase 21：matchedTransitionSource 让 AttendanceView 从卡位 zoom 放大出来
            NavigationLink(destination:
                AttendanceView(isEmbedded: true)
                    .navigationTransition(.zoom(sourceID: "attendance.card", in: attendanceNamespace))
            ) {
                Color.clear
            }
            .buttonStyle(.plain)
            .opacity(0.0001) // 不遮住视觉但保留命中

            attendanceWidgetContent
        }
        .bsGlassCard()
        .matchedTransitionSource(id: "attendance.card", in: attendanceNamespace)
        .task { await attendance.loadToday() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今日打卡 \(statusCapsuleText)")
        // Phase 21：clockState 变化时整体驱动 morph 动画（spring overshoot）
        .animation(BsMotion.Anim.overshoot, value: attendance.clockState)
    }

    private var attendanceWidgetContent: some View {
        ZStack {
            // 流体卡内微氛围 —— 状态色 RadialGradient，唯一残留的"光"
            RadialGradient(
                colors: [stateAccent.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 240
            )
            .blur(radius: 40)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                attendanceHeaderRow

                // Phase 23：未打卡态换 welcoming 空态；已打卡 / 已完成走完整 hero
                if attendance.clockState == .ready && attendance.today?.clockIn == nil {
                    attendanceWelcomeRow
                } else {
                    attendanceHeroRow
                }

                attendanceFooterSlot
            }
            .padding(BsSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 未打卡态的欢迎视图 —— 取代 "--:-- × 3" 空数据堆砌。
    /// 左侧品牌色 SF Symbol "sun.max.fill"（日出图标）+ 右侧引导文案。
    private var attendanceWelcomeRow: some View {
        HStack(alignment: .center, spacing: BsSpacing.md) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.palette)
                .foregroundStyle(BsColor.brandCoral, BsColor.brandMint)
                .frame(width: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("开始你的一天")
                    .font(.custom("Outfit-SemiBold", size: 20))
                    .foregroundStyle(BsColor.ink)
                Text("点击下方按钮完成上班打卡")
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: Header — "今日打卡" + date + status pill

    private var attendanceHeaderRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日打卡")
                    .font(BsTypography.cardTitle)
                    .foregroundStyle(BsColor.ink)
                Text(formattedFullDate)
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer()
            attendanceStatusPill
        }
    }

    /// 流体半透状态胶囊 —— 不是 solid fill 按钮,而是 glass-tinted badge。
    private var attendanceStatusPill: some View {
        Label {
            Text(statusCapsuleText)
        } icon: {
            Image(systemName: statusCapsuleIcon)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(stateAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(stateAccent.opacity(0.35)), in: Capsule())
        // Phase 21：跨 clockState 切态，胶囊 morph（而不是替换），iOS 26 签名行为
        .glassEffectID("attendance.status", in: attendanceNamespace)
    }

    // MARK: Hero row — ProgressRing + secondary times column

    private var attendanceHeroRow: some View {
        HStack(alignment: .center, spacing: BsSpacing.lg) {
            attendanceProgressRing
            attendanceSecondaryTimesColumn
            Spacer(minLength: 0)
        }
    }

    /// 英雄进度环 —— 92x92,state accent 色,内嵌工时 + 副标。
    /// TimelineView(.periodic, by: 60) 让进度与工时每分钟自刷新,无需额外 timer state。
    private var attendanceProgressRing: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let progress = dayProgress(at: context.date)
            let durationText = formatWorkDuration(
                from: attendance.today?.clockIn,
                to: attendance.today?.clockOut ?? (attendance.clockState == .clockedIn ? context.date : nil)
            )

            ZStack {
                Circle()
                    .stroke(stateAccent.opacity(0.15), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        stateAccent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(BsMotion.Anim.overshoot, value: progress)

                // Phase 24：成功打卡 ripple —— 从环中心向外扩散，0.8s 自消散
                BsRippleLayer(trigger: punchRipple, color: stateAccent)

                VStack(spacing: 2) {
                    Text(durationText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(BsColor.ink)
                    Text("今日工时")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
            .frame(width: 92, height: 92)
        }
    }

    /// 右侧 Linear-style 编辑副栏: 打卡 / 下班 两行,label + rounded time。
    private var attendanceSecondaryTimesColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            attendanceSecondaryRow(
                label: "打卡",
                time: formatClockTime(attendance.today?.clockIn)
            )
            attendanceSecondaryRow(
                label: "下班",
                time: formatClockTime(attendance.today?.clockOut)
            )
        }
    }

    private func attendanceSecondaryRow(label: String, time: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 32, alignment: .leading)
            Text(time)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(BsColor.ink)
        }
    }

    // MARK: Footer slot — CTA button OR "已完成" inkMuted center caption

    @ViewBuilder
    private var attendanceFooterSlot: some View {
        switch attendance.clockState {
        case .ready, .clockedIn:
            attendancePunchButton
        case .done:
            HStack {
                Spacer()
                Text("已完成 · 今日辛苦了")
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(BsColor.inkMuted)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    /// 流体半透 CTA —— glassEffect tint,不再是实色 red/green 按钮。
    /// .ready → azure "上班打卡",.clockedIn → danger "下班打卡"。
    /// Phase 20：打卡是 Dashboard 屏幕的"主 CTA"，用 BsBrandButton 三色渐变填色。
    /// 上班打卡（azure ambient 背景）/ 下班打卡都走同一个品牌按钮——**一屏一个**集中爆发点。
    private var attendancePunchButton: some View {
        let isClockIn = attendance.clockState == .ready
        let icon = isClockIn ? "clock.fill" : "clock.badge.checkmark"
        let title = isClockIn ? "上班打卡" : "下班打卡"

        return BsBrandButton(
            size: .large,
            isLoading: attendance.isLoading,
            action: {
                Task {
                    await attendance.punch()
                    if attendance.errorMessage != nil {
                        Haptic.error()
                    } else {
                        // Phase 24：成功后触发 progress ring ripple
                        await MainActor.run { punchRipple += 1 }
                    }
                }
            }
        ) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
            }
            .foregroundStyle(.white)
        }
        // Phase 21：跨 state morph —— 上班打卡 ↔ 下班打卡 玻璃 "流" 变不是切换
        .glassEffectID("attendance.cta", in: attendanceNamespace)
    }

    // MARK: Formatters

    private func formatClockTime(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func formatWorkDuration(from clockIn: Date?, to clockOut: Date?) -> String {
        guard let clockIn else { return "--:--" }
        let end = clockOut ?? Date()
        let interval = end.timeIntervalSince(clockIn)
        guard interval > 0 else { return "--:--" }
        let hours = Int(interval / 3600)
        let mins = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        return String(format: "%d:%02d", hours, mins)
    }

    // MARK: - Apps Grid (Phase 25 工作台核心)
    //
    // 飞书/钉钉"工作台"pattern：顶部品牌色大图标 + 底部小名称 + RBAC 门控。
    // 4 列网格，按语义分类：日常 / 协作 / 创作 / 分析 / 招聘。
    //
    // RBAC 不通过的 tile 不显；分类下所有 tile 都不通过则整组隐藏。

    @Environment(SessionManager.self) private var sessionManager

    private var effectiveCapabilities: [Capability] {
        RBACManager.shared.getEffectiveCapabilities(for: sessionManager.currentProfile)
    }

    private func hasCap(_ cap: Capability) -> Bool {
        RBACManager.shared.hasCapability(cap, in: effectiveCapabilities)
    }

    private var isAdminTier: Bool {
        let primaryRole = RBACManager.shared
            .migrateLegacyRole(sessionManager.currentProfile?.role)
            .primaryRole
        return primaryRole == .admin || primaryRole == .superadmin
    }

    @ViewBuilder
    private var appsGridSection: some View {
        // 5 人评审修正：ONE 外层 glass 卡包所有 section + section 间 Divider 分隔。
        // 不是 v1 "每组一张卡"（太重），也不是 v2 "无卡裸奔"（太散）。
        // 分类策略：按**用户动作频次 + 语义亲缘**，3-4 组。
        VStack(alignment: .leading, spacing: BsSpacing.lg) {

            // —— 常用 (高频每日用，无权限门) ——
            BsAppGrid("常用") {
                BsAppTile(name: "考勤", systemImage: "clock.fill", tint: BsColor.brandAzure) {
                    AnyView(AttendanceView(isEmbedded: true))
                }
                BsAppTile(name: "排班", systemImage: "calendar", tint: BsColor.brandAzure) {
                    AnyView(ScheduleView(isEmbedded: true))
                }
                BsAppTile(name: "请假", systemImage: "calendar.badge.minus", tint: BsColor.brandMint) {
                    AnyView(LeavesView(client: supabase, isEmbedded: true))
                }
                BsAppTile(name: "日报", systemImage: "doc.text.fill", tint: BsColor.brandMint) {
                    AnyView(ReportingListView(viewModel: ReportingViewModel(client: supabase), isEmbedded: true))
                }
                BsAppTile(name: "周报", systemImage: "doc.richtext.fill", tint: BsColor.brandMint) {
                    AnyView(ReportingListView(viewModel: ReportingViewModel(client: supabase), isEmbedded: true))
                }
                BsAppTile(name: "通知", systemImage: "bell.fill", tint: BsColor.brandCoral) {
                    AnyView(NotificationListView(viewModel: NotificationListViewModel(client: supabase), isEmbedded: true))
                }
            }

            // —— 协作 (跟人有关) ——
            BsAppGrid("协作") {
                BsAppTile(name: "公告", systemImage: "megaphone.fill", tint: BsColor.brandCoral) {
                    AnyView(AnnouncementsListView(viewModel: AnnouncementsListViewModel(client: supabase), isEmbedded: true))
                }
                BsAppTile(name: "团队", systemImage: "person.3.fill", tint: BsColor.brandAzure) {
                    AnyView(TeamDirectoryView(isEmbedded: true))
                }
                BsAppTile(name: "活动", systemImage: "sparkle", tint: BsColor.brandMint) {
                    AnyView(ActivityFeedView(viewModel: ActivityFeedViewModel(client: supabase), isEmbedded: true))
                }
                BsAppTile(name: "知识库", systemImage: "book.fill", tint: BsColor.brandAzure) {
                    AnyView(KnowledgeListView(viewModel: KnowledgeListViewModel(client: supabase), isEmbedded: true))
                }
            }

            // —— 业务 (项目/财务/HR/AI 聚合；按权限动态) ——
            let showBusiness = hasCap(.finance_ops) || hasCap(.hr_ops) || hasCap(.recruitment_approval)
                || hasCap(.ai_media_analysis) || hasCap(.ai_resume_screening) || hasCap(.ai_finance_docs)
                || isAdminTier
            if showBusiness || true {  // 项目/OKR/交付物 任何角色都可见
                BsAppGrid("业务") {
                    // 项目类 —— 全员可见
                    BsAppTile(name: "项目", systemImage: "rectangle.3.group.fill", tint: BsColor.brandAzure) {
                        AnyView(ProjectListView(viewModel: ProjectListViewModel(client: supabase), isEmbedded: true))
                    }
                    BsAppTile(name: "OKR", systemImage: "target", tint: BsColor.brandAzure) {
                        AnyView(OKRListView(viewModel: OKRListViewModel(client: supabase), isEmbedded: true))
                    }
                    BsAppTile(name: "交付物", systemImage: "shippingbox.fill", tint: BsColor.brandMint) {
                        AnyView(DeliverableListView(viewModel: DeliverableListViewModel(client: supabase), isEmbedded: true))
                    }

                    // 财务类 —— 权限门
                    if hasCap(.finance_ops) || isAdminTier {
                        BsAppTile(name: "财务", systemImage: "yensign.circle.fill", tint: BsColor.brandCoral) {
                            AnyView(FinanceView(client: supabase, isEmbedded: true))
                        }
                        BsAppTile(name: "薪资", systemImage: "banknote.fill", tint: BsColor.brandCoral) {
                            AnyView(PayrollListView(viewModel: PayrollListViewModel(client: supabase), isEmbedded: true))
                        }
                    }

                    // 招聘 —— HR 权限
                    if hasCap(.hr_ops) || hasCap(.recruitment_approval) || isAdminTier {
                        BsAppTile(name: "招聘", systemImage: "briefcase.fill", tint: BsColor.brandCoral) {
                            AnyView(HiringCenterView(isEmbedded: true))
                        }
                    }

                    // AI 分析 —— AI 权限
                    if hasCap(.ai_media_analysis) || hasCap(.ai_resume_screening) || hasCap(.ai_finance_docs) || isAdminTier {
                        BsAppTile(name: "AI 分析", systemImage: "brain.head.profile", tint: BsColor.brandMint) {
                            AnyView(AIAnalysisView(isEmbedded: true))
                        }
                    }
                }
            }

            // —— 管理 (admin+ 专属) ——
            if isAdminTier {
                BsAppGrid("管理") {
                    BsAppTile(name: "管理中心", systemImage: "shield.lefthalf.filled", tint: BsColor.brandAzure) {
                        AnyView(AdminCenterView(isEmbedded: true))
                    }
                    BsAppTile(name: "用户", systemImage: "person.crop.rectangle.stack.fill", tint: BsColor.brandAzure) {
                        AnyView(AdminUsersView(canAssignPrivileges: true, isEmbedded: true))
                    }
                    BsAppTile(name: "审计", systemImage: "doc.text.magnifyingglass", tint: BsColor.inkMuted) {
                        AnyView(AdminAuditView(isEmbedded: true))
                    }
                    BsAppTile(name: "广播", systemImage: "dot.radiowaves.left.and.right", tint: BsColor.brandCoral) {
                        AnyView(AdminBroadcastView(isEmbedded: true))
                    }
                    BsAppTile(name: "组织配置", systemImage: "building.2.fill", tint: BsColor.inkMuted) {
                        AnyView(AdminOrgConfigView(isEmbedded: true))
                    }
                    BsAppTile(name: "公休", systemImage: "calendar.badge.plus", tint: BsColor.brandMint) {
                        AnyView(AdminHolidaysView(isEmbedded: true))
                    }
                }
            }
        }
    }

    // MARK: - Schedule

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
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Toolbar buttons

    /// NavigationBar 中央品牌槽 —— Logo + Azure→Mint 渐变 BrainStorm+。
    /// 原生 iOS 范式（Weather / Calendar 的顶部标题做法），取代之前
    /// 夹在 Large Title 上方那条 BrandStrip 的奇怪位置。
    private var brandToolbarItem: some View {
        HStack(spacing: 6) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)

            Text("BrainStorm+")
                .font(.custom("Outfit-Bold", size: 15))
                .foregroundStyle(BsColor.ink)  // 实色，不渐变。品牌靠 logo icon 自身三色 + TabBar tint
                .tracking(-0.2)
        }
        .accessibilityLabel("BrainStorm+")
    }

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
    }

    /// Phase 25 v3：「面板」启动台入口。NavBar trailing 首位。
    /// square.grid.3x3 图标 + Azure 玻璃圆按钮，iOS 原生点击 + 上升 sheet。
    private var launcherButton: some View {
        Button {
            Haptic.light()
            showLauncher = true
        } label: {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BsColor.brandAzure)
                .frame(width: 32, height: 32)
                .glassEffect(
                    .regular.tint(BsColor.brandAzure.opacity(0.22)).interactive(),
                    in: Circle()
                )
        }
        .accessibilityLabel("面板")
    }

    private var notificationButton: some View {
        NavigationLink(destination: ActionItemHelper.destination(for: .notifications)) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BsColor.ink)
                    .frame(width: 32, height: 32)
                // Unread badge - 原生 iOS 小红点
                Circle()
                    .fill(BsColor.brandCoral)
                    .frame(width: 7, height: 7)
                    .offset(x: -6, y: 6)
            }
        }
    }


    // MARK: - Background (blob tint, 克制,让 List 透出颜色)

    private var backgroundLayer: some View {
        ZStack {
            BsColor.pageBackground.ignoresSafeArea()

            GeometryReader { proxy in
                Circle()
                    .fill(BsColor.brandAzure.opacity(0.08))
                    .frame(width: proxy.size.width * 1.5, height: proxy.size.width * 1.5)
                    .blur(radius: 80)
                    .offset(x: -proxy.size.width * 0.5, y: -proxy.size.height * 0.2)

                Circle()
                    .fill(BsColor.brandMint.opacity(0.06))
                    .frame(width: proxy.size.width * 1.2, height: proxy.size.width * 1.2)
                    .blur(radius: 60)
                    .offset(x: proxy.size.width * 0.3, y: proxy.size.height * 0.4)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Role-Branched Sections

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
