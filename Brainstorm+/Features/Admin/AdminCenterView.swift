import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.1 — 管理后台 (Admin Center)
// Parity target: Web `BrainStorm+-Web/src/app/dashboard/admin/page.tsx`.
// 顶层列表风格（类似 Settings），按子功能拆分 NavigationLink。
// 入口受限于 primaryRole ∈ {superadmin, admin}；更细粒度在子视图内部再次校验。
// ══════════════════════════════════════════════════════════════════

public struct AdminCenterView: View {
    @StateObject private var viewModel = AdminCenterViewModel()
    @Environment(SessionManager.self) private var sessionManager

    /// Bug-fix(滑动判定为点击 + 震动): NavigationLink in VStack inside ScrollView
    /// 在 iOS 26 触发太敏感 —— 手指放上去稍微停留就触发 tap (NavigationLink push +
    /// contextMenu preview haptic),用户想滑动反馈成"点击"。
    /// 改用 Button + .navigationDestination(item:) 的程序化导航:Button 在
    /// ScrollView 里有正确的 tap-vs-drag 判定 (drag 超过阈值会自动 cancel tap)。
    @State private var pushTarget: AdminModuleRoute? = nil

    /// Identifiable enum for programmatic admin module navigation. Each case
    /// resolves to a distinct AdminXxxView destination in the central
    /// `.navigationDestination(item:)` modifier below.
    fileprivate enum AdminModuleRoute: Identifiable, Hashable {
        case users
        case evaluations
        case org
        case holidays
        case geofence
        case attendanceExemption
        case leaveQuota
        case teamReports
        case aiSettings
        case audit

        var id: String {
            switch self {
            case .users: return "users"
            case .evaluations: return "evaluations"
            case .org: return "org"
            case .holidays: return "holidays"
            case .geofence: return "geofence"
            case .attendanceExemption: return "attendanceExemption"
            case .leaveQuota: return "leaveQuota"
            case .teamReports: return "teamReports"
            case .aiSettings: return "aiSettings"
            case .audit: return "audit"
            }
        }
    }

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(isEmbedded: Bool = false) {
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
            if viewModel.canEnterAdmin {
                content
            } else {
                BsEmptyState(
                    title: "无权访问",
                    systemImage: "lock",
                    description: "只有管理员可以访问"
                )
            }
        }
        .navigationTitle("管理后台")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.bind(sessionProfile: sessionManager.currentProfile)
            if viewModel.canEnterAdmin {
                await viewModel.loadStats()
            }
        }
        .refreshable {
            viewModel.bind(sessionProfile: sessionManager.currentProfile)
            if viewModel.canEnterAdmin {
                await viewModel.loadStats()
            }
        }
        .zyErrorBanner($viewModel.errorMessage)
        // Bug-fix(滑动判定为点击 + 震动): 程序化导航 destination,配合 modulesList 内
        // Button + pushTarget binding,替代旧 NavigationLink 的过敏感 tap 触发。
        .navigationDestination(item: $pushTarget) { route in
            switch route {
            case .users:
                AdminUsersView(canAssignPrivileges: viewModel.canAssignPrivileges, isEmbedded: true)
            case .evaluations:
                AdminEvaluationsView()
            case .org:
                AdminOrgConfigView(isEmbedded: true)
            case .holidays:
                AdminHolidaysView(isEmbedded: true)
            case .geofence:
                AdminGeofenceView()
            case .attendanceExemption:
                AdminAttendanceExemptionView()
            case .leaveQuota:
                AdminLeaveQuotaView()
            case .teamReports:
                AdminTeamReportsView(isEmbedded: true)
            case .aiSettings:
                AdminAISettingsView()
            case .audit:
                AdminAuditView(isEmbedded: true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: BsSpacing.lg + 4) {
                headerCard
                statsGrid
                modulesList
                Spacer(minLength: BsSpacing.xxl)
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.md)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
    }

    private var headerCard: some View {
        BsContentCard(padding: .medium) {
            HStack(spacing: BsSpacing.md + 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                        .fill(BsColor.brandAzure.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.title2)
                        .foregroundStyle(BsColor.brandAzure)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("管理后台")
                        .font(BsTypography.cardTitle)
                        .foregroundStyle(BsColor.ink)
                    Text("系统管理 · 用户维护 · 权限配置")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                Spacer()
            }
        }
    }

    private var statsGrid: some View {
        let items: [(icon: String, label: String, value: Int, color: Color)] = [
            ("person.3.fill", "总用户", viewModel.stats.totalUsers, BsColor.brandAzure),
            ("bolt.fill", "今日活跃", viewModel.stats.activeToday, BsColor.success),
            ("checkmark.circle.fill", "任务总数", viewModel.stats.totalTasks, BsColor.brandCoral),
            ("folder.fill", "项目总数", viewModel.stats.totalProjects, BsColor.brandMint)
        ]
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: BsSpacing.md), GridItem(.flexible(), spacing: BsSpacing.md)],
            spacing: BsSpacing.md
        ) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                statCard(icon: item.icon, label: item.label, value: item.value, color: item.color)
            }
        }
    }

    private func statCard(icon: String, label: String, value: Int, color: Color) -> some View {
        BsContentCard(padding: .medium) {
            VStack(alignment: .leading, spacing: BsSpacing.sm + 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                }
                Text(label.uppercased())
                    .font(BsTypography.meta)
                    .tracking(1.2)
                    .foregroundStyle(BsColor.inkMuted)
                Text("\(value)")
                    .font(BsTypography.statMedium)
                    .foregroundStyle(BsColor.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
    }

    private var modulesList: some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            BsSectionHeader("管理模块")
                .padding(.leading, BsSpacing.sm)

            BsContentCard(padding: .none) {
                VStack(spacing: 0) {
                if viewModel.canManagePeople {
                    row(
                        icon: "person.2.fill",
                        color: BsColor.brandAzure,
                        title: "用户管理",
                        subtitle: "创建 · 编辑 · 角色 · 能力包",
                        route: .users
                    )
                    divider()
                }

                if viewModel.canManageEvaluations {
                    row(
                        icon: "sparkles",
                        color: .purple,
                        title: "AI 评分中心",
                        subtitle: "月度评估 · 五维评分 · 风险复核",
                        route: .evaluations
                    )
                    divider()
                }

                if viewModel.canManageOrg {
                    row(
                        icon: "building.2.fill",
                        color: .teal,
                        title: "组织架构",
                        subtitle: "部门 · 职位",
                        route: .org
                    )
                    divider()
                }

                if viewModel.canManageHolidays {
                    row(
                        icon: "calendar.badge.plus",
                        color: .orange,
                        title: "公休日历",
                        subtitle: "添加 · 删除 · 分区域",
                        route: .holidays
                    )
                    divider()
                }

                if viewModel.canManageAttendanceRules {
                    row(
                        icon: "location.circle.fill",
                        color: .mint,
                        title: "地理围栏",
                        subtitle: "多点打卡中心 · 半径 · 地图预览",
                        route: .geofence
                    )
                    divider()
                    row(
                        icon: "shield.lefthalf.filled",
                        color: .cyan,
                        title: "弹性考勤豁免",
                        subtitle: "部门 / 员工 · 免围栏 · 弹性工时",
                        route: .attendanceExemption
                    )
                    divider()
                }

                if viewModel.canManageLeaveQuota {
                    row(
                        icon: "calendar.badge.clock",
                        color: .indigo,
                        title: "调休额度",
                        subtitle: "按员工月度额度 · 批量设置",
                        route: .leaveQuota
                    )
                    divider()
                }

                // 广播通知 — 已合并进"公告通知"(发布公告时勾选"同时推送给所有人")。
                // 入口收敛：只保留单一"公告"功能位面，避免用户困惑。

                if viewModel.canManagePeople || viewModel.canEnterAdmin {
                    row(
                        icon: "doc.text.magnifyingglass",
                        color: BsColor.brandMint,
                        title: "全员日报周报",
                        subtitle: "查看团队成员的日报和周报",
                        route: .teamReports
                    )
                    divider()
                }

                if viewModel.canManageAISettings {
                    row(
                        icon: "cpu",
                        color: .indigo,
                        title: "AI 设置",
                        subtitle: "供应商 · 默认模型 · 降级链 · 月度评分",
                        route: .aiSettings
                    )
                    divider()
                }

                if viewModel.canViewAudit {
                    row(
                        icon: "list.bullet.clipboard.fill",
                        color: .purple,
                        title: "操作审计",
                        subtitle: "查看管理操作日志",
                        route: .audit
                    )
                }
                }
            }
        }
    }

    /// Bug-fix(滑动判定为点击 + 震动): 用 Button + pushTarget 替代
    /// NavigationLink。Button 在 ScrollView/VStack 里正确处理 tap-vs-drag,
    /// 滑动手指超过阈值时自动 cancel tap,避免误推 destination。
    @ViewBuilder
    private func row(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        route: AdminModuleRoute
    ) -> some View {
        Button {
            pushTarget = route
        } label: {
            HStack(spacing: BsSpacing.md + 2) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(color.opacity(0.25), lineWidth: 0.5)
                        )
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)
                    Text(subtitle)
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BsColor.inkFaint)
            }
            .padding(.vertical, BsSpacing.md + 2)
            .padding(.horizontal, BsSpacing.lg)
            .contentShape(Rectangle())
            // Bug-fix(滑动难滑): 移除 .bsInteractiveFeel(.row) —— 它内部用
            // simultaneousGesture(DragGesture(minimumDistance:0)) 抢占父
            // ScrollView 的 drag 跟踪,导致管理模块列表滑动被吃掉,且每次手指
            // 接触就触发 haptic.light()。Button 自带的按压反馈已足够,UX 上
            // 也消除了"轻触即震"的问题。
        }
        .buttonStyle(.plain)
    }

    private func divider() -> some View {
        Divider()
            .background(BsColor.borderSubtle)
            .padding(.leading, 64)
    }
}
