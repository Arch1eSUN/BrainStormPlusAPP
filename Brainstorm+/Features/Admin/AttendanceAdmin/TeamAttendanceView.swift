import SwiftUI
import UIKit

// ══════════════════════════════════════════════════════════════════
// TeamAttendanceView —— 全员考勤（Admin 专属）
//
// Phase 0b：填补 iOS 缺失的 "admin 看团队打卡" 功能。
//
// 内容：
//   • 顶部日期选择（默认今日）+ 部门筛选（Menu）
//   • 快览 chip：出勤 N / 未打卡 N
//   • 员工列表：头像 + 姓名/部门 + 状态 pill + 打卡/下班时间
//   • 搜索（姓名 / 部门）
//   • Pull-to-refresh
//
// 架构：按 plan 2.8 签名，接受 isEmbedded 参数化（为 Phase 3 准备）
// ══════════════════════════════════════════════════════════════════

public struct TeamAttendanceView: View {
    @StateObject private var viewModel = TeamAttendanceViewModel()

    let isEmbedded: Bool

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
        List {
            // Section header —— 日期 + 部门筛选 + 快览
            Section {
                headerControls
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
            }

            // 员工列表
            if viewModel.filteredRows.isEmpty && !viewModel.isLoading {
                Section {
                    BsEmptyState(
                        title: viewModel.searchQuery.isEmpty ? "暂无数据" : "没有匹配的员工",
                        systemImage: viewModel.searchQuery.isEmpty ? "person.2.slash" : "magnifyingglass",
                        description: viewModel.searchQuery.isEmpty ?
                            "当前日期或部门下没有员工打卡记录" :
                            "换个关键词再试"
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(viewModel.filteredRows) { row in
                        memberRow(row)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .searchable(
            text: $viewModel.searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索姓名 / 部门"
        )
        .refreshable {
            // Haptic removed: 用户反馈滑动场景不应震动
            await viewModel.load()
        }
        // 主入口：用 selectedDate 作为 task id —— 切日期时 SwiftUI
        // 自动重启该 task。第一次触发时 rows 为空 → load()；之后每次切
        // 日期 id 变 → 强制 load()。
        //
        // 注意：VM init 已经主动发起一次 prefetch。这条 .task 是第二道防线：
        // 当 SwiftUI 把 NavigationLink 的 phantom 实例 cancel 掉（连带 prefetch
        // task 一起 cancel），可见实例 .task fire 时会再发一次，由 VM 内部
        // performLoad 的 inFlight 去重保证不会重复请求。
        .task(id: viewModel.selectedDate) {
            await viewModel.load()
        }
        // 第三道防线：onAppear 时若仍然 rows 为空 + 非加载中（即前两步全失败），
        // 再补一发。loadIfNeeded 幂等。
        .onAppear {
            if viewModel.rows.isEmpty && !viewModel.isLoading {
                Task { await viewModel.loadIfNeeded() }
            }
        }
        // Scene foregrounding（用户从后台回到 app）也补刷一次，避免后台
        // 期间日期跨天后看到上一日的旧数据。
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.load() }
        }
        .zyErrorBanner($viewModel.errorMessage)
        .navigationTitle("全员考勤")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Header controls

    private var headerControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 日期选择器
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(BsColor.brandAzure)
                DatePicker("日期", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(BsColor.brandAzure)

                Spacer()

                // 部门筛选
                Menu {
                    Button {
                        viewModel.departmentFilter = nil
                    } label: {
                        Label("全部部门", systemImage: viewModel.departmentFilter == nil ? "checkmark" : "")
                    }
                    Divider()
                    ForEach(viewModel.allDepartments, id: \.self) { dept in
                        Button {
                            viewModel.departmentFilter = dept
                        } label: {
                            Label(dept, systemImage: viewModel.departmentFilter == dept ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(viewModel.departmentFilter ?? "全部")
                            .lineLimit(1)
                    }
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(BsColor.brandAzure)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(BsColor.brandAzure.opacity(0.14)).interactive(), in: Capsule())
                }
            }

            // 快览 chips
            HStack(spacing: 10) {
                summaryChip(label: "已出勤", count: viewModel.presentCount, tint: BsColor.brandMint)
                summaryChip(label: "未打卡", count: viewModel.absentCount, tint: BsColor.brandCoral)
                Spacer()
            }
        }
    }

    private func summaryChip(label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(BsColor.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10), in: Capsule())
    }

    // MARK: - Member row

    private func memberRow(_ row: TeamAttendanceViewModel.Row) -> some View {
        HStack(spacing: 12) {
            avatar(for: row.profile)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.fullName)
                    .font(BsTypography.body.weight(.semibold))
                    .foregroundStyle(BsColor.ink)
                if !row.department.isEmpty {
                    Text(row.department)
                        .font(BsTypography.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                statusPill(for: row)
                HStack(spacing: 4) {
                    Text(row.clockInText)
                    Text("-")
                        .foregroundStyle(BsColor.inkFaint)
                    Text(row.clockOutText)
                }
                .font(.system(.caption, design: .rounded, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(BsColor.inkMuted)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func avatar(for profile: Profile) -> some View {
        ZStack {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.12))
            Text(String(profile.fullName?.prefix(1) ?? "?"))
                .font(BsTypography.cardTitle.weight(.semibold))
                .foregroundStyle(BsColor.brandAzure)
        }
        .frame(width: 40, height: 40)
        .accessibilityLabel(profile.fullName ?? "用户")
    }

    @ViewBuilder
    private func statusPill(for row: TeamAttendanceViewModel.Row) -> some View {
        let (tint, iconName): (Color, String) = {
            switch row.statusLabel {
            case "已打卡":  return (BsColor.brandMint, "clock.fill")
            case "已下班":  return (BsColor.brandMint, "checkmark.circle.fill")
            case "请假":    return (BsColor.warning, "bed.double.fill")
            case "出差":    return (BsColor.brandAzure, "airplane")
            case "外勤":    return (BsColor.brandCoral, "figure.walk")
            default:       return (BsColor.inkFaint, "clock")
            }
        }()

        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(.caption2))
            Text(row.statusLabel)
                .font(.system(.caption2, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

#Preview {
    TeamAttendanceView()
}
