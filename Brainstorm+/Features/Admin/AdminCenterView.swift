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

    public init() {}

    public var body: some View {
        Group {
            if viewModel.canEnterAdmin {
                content
            } else {
                ContentUnavailableView(
                    "无权访问",
                    systemImage: "lock",
                    description: Text("只有管理员可以访问")
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
        .background(BsAmbientBackground(includeCoral: true))
    }

    private var headerCard: some View {
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
        .padding(BsSpacing.md)
        .bsGlassCard()
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
        }
        .padding(BsSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bsGlassCard()
    }

    private var modulesList: some View {
        VStack(alignment: .leading, spacing: BsSpacing.md) {
            BsSectionHeader("管理模块")
                .padding(.leading, BsSpacing.sm)

            VStack(spacing: 0) {
                if viewModel.canManagePeople {
                    row(
                        icon: "person.2.fill",
                        color: BsColor.brandAzure,
                        title: "用户管理",
                        subtitle: "创建 · 编辑 · 角色 · 能力包"
                    ) {
                        AdminUsersView(canAssignPrivileges: viewModel.canAssignPrivileges)
                    }
                    divider()
                }

                if viewModel.canManageEvaluations {
                    row(
                        icon: "sparkles",
                        color: .purple,
                        title: "AI 评分中心",
                        subtitle: "月度评估 · 五维评分 · 风险复核"
                    ) {
                        AdminEvaluationsView()
                    }
                    divider()
                }

                if viewModel.canManageOrg {
                    row(
                        icon: "building.2.fill",
                        color: .teal,
                        title: "组织架构",
                        subtitle: "部门 · 职位"
                    ) {
                        AdminOrgConfigView()
                    }
                    divider()
                }

                if viewModel.canManageHolidays {
                    row(
                        icon: "calendar.badge.plus",
                        color: .orange,
                        title: "公休日历",
                        subtitle: "添加 · 删除 · 分区域"
                    ) {
                        AdminHolidaysView()
                    }
                    divider()
                }

                if viewModel.canManageAttendanceRules {
                    row(
                        icon: "location.circle.fill",
                        color: .mint,
                        title: "地理围栏",
                        subtitle: "多点打卡中心 · 半径 · 地图预览"
                    ) {
                        AdminGeofenceView()
                    }
                    divider()
                    row(
                        icon: "shield.lefthalf.filled",
                        color: .cyan,
                        title: "弹性考勤豁免",
                        subtitle: "部门 / 员工 · 免围栏 · 弹性工时"
                    ) {
                        AdminAttendanceExemptionView()
                    }
                    divider()
                }

                if viewModel.canManageLeaveQuota {
                    row(
                        icon: "calendar.badge.clock",
                        color: .indigo,
                        title: "调休额度",
                        subtitle: "按员工月度额度 · 批量设置"
                    ) {
                        AdminLeaveQuotaView()
                    }
                    divider()
                }

                if viewModel.canAssignPrivileges {
                    row(
                        icon: "megaphone.fill",
                        color: .pink,
                        title: "广播通知",
                        subtitle: "向全员推送系统消息"
                    ) {
                        AdminBroadcastView()
                    }
                    divider()
                }

                if viewModel.canManageAISettings {
                    row(
                        icon: "cpu",
                        color: .indigo,
                        title: "AI 设置",
                        subtitle: "供应商 · 默认模型 · 降级链 · 月度评分"
                    ) {
                        AdminAISettingsView()
                    }
                    divider()
                }

                if viewModel.canViewAudit {
                    row(
                        icon: "list.bullet.clipboard.fill",
                        color: .purple,
                        title: "操作审计",
                        subtitle: "查看管理操作日志"
                    ) {
                        AdminAuditView()
                    }
                }
            }
            .bsGlassCard()
        }
    }

    @ViewBuilder
    private func row<Destination: View>(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
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
            .bsInteractiveFeel(.row)
        }
        .buttonStyle(.plain)
    }

    private func divider() -> some View {
        Divider()
            .background(BsColor.borderSubtle)
            .padding(.leading, 64)
    }
}
