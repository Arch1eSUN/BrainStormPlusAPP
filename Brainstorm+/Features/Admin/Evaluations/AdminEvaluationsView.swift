import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.6a — AI 月度评估管理（iOS 端）
// Parity target: Web `src/app/dashboard/admin/evaluations/page.tsx`
//   + _components/evaluations-matrix.tsx
//
// iOS 适配：Web 用员工×指标的宽矩阵（5 + 总分 = 6 列），在 iPhone 宽度下
// 读起来很崩。这里把矩阵展平成 List：每行 = 1 位员工的当月评估卡片，
// 显示姓名 / 部门 / 总分 pill / 状态徽章 / 触发来源；点击进 Detail 查看全
// 五维 + 叙述 + 风险标签。
// ══════════════════════════════════════════════════════════════════

public struct AdminEvaluationsView: View {
    @StateObject private var vm = AdminEvaluationsViewModel()
    @Environment(SessionManager.self) private var sessionManager
    @State private var monthPickerDate: Date = Date()
    @State private var showBatchSheet: Bool = false

    public init() {}

    public var body: some View {
        Group {
            if vm.canAccess {
                content
            } else {
                BsEmptyState(
                    title: "无权访问",
                    systemImage: "lock.shield",
                    description: "需要 AI 月度评估能力包或超级管理员权限"
                )
            }
        }
        .navigationTitle("AI 评分中心")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            vm.bind(sessionProfile: sessionManager.currentProfile)
            syncMonthPickerDate()
            if vm.canAccess { await vm.reload() }
        }
        .refreshable {
            vm.bind(sessionProfile: sessionManager.currentProfile)
            if vm.canAccess { await vm.reload() }
        }
        .zyErrorBanner($vm.errorMessage)
        .sheet(isPresented: $showBatchSheet) {
            AdminEvaluationBatchSheet(
                month: vm.month,
                userIds: vm.filteredRows.map { $0.userId },
                onTriggered: { _ in
                    Task { await vm.reload() }
                },
                runTrigger: { ids, force in
                    await vm.triggerBatch(userIds: ids, forceRegenerate: force)?.triggeredCount
                }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        List {
            Section {
                monthControl
                filterControls
                summaryChips
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if vm.isLoading && vm.rows.isEmpty {
                // Bug-fix(loading 一致性): section-level loading 用 .small（和 inline 风格一致，list 里不要 .large）。
                Section { ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 24) }
                    .listRowBackground(Color.clear)
            } else if vm.filteredRows.isEmpty {
                Section {
                    BsEmptyState(
                        title: vm.rows.isEmpty ? "本月暂无员工数据" : "没有匹配的记录",
                        systemImage: "person.fill.questionmark",
                        description: vm.rows.isEmpty
                            ? "请切换月份或确认该月份已有在职员工"
                            : "尝试调整筛选条件"
                    )
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(vm.filteredRows) { row in
                        NavigationLink {
                            AdminEvaluationDetailView(row: row, month: vm.month)
                        } label: {
                            rowCell(row)
                        }
                    }
                } header: {
                    Text("员工列表 · \(vm.filteredRows.count) 人")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Haptic removed: 用户反馈 toolbar 按钮过密震动
                    showBatchSheet = true
                } label: {
                    Image(systemName: "bolt.horizontal.circle.fill")
                }
                .accessibilityLabel("批量评估")
            }
        }
    }

    // ── Month stepper + picker ──────────────────────────────────
    private var monthControl: some View {
        HStack(spacing: 10) {
            Button {
                // Haptic removed: 用户反馈月份切换按钮过密震动
                Task { await vm.shiftMonth(by: -1); syncMonthPickerDate() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .padding(8)
                    .background(Circle().fill(BsColor.brandAzure.opacity(0.1)))
                    .foregroundStyle(BsColor.brandAzure)
            }
            .accessibilityLabel("上一月")

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.month)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BsColor.ink)
                Text("月度评估队列")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }

            Spacer()

            DatePicker(
                "选择月份",
                selection: $monthPickerDate,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .onChange(of: monthPickerDate) { _, newValue in
                let cal = Calendar(identifier: .gregorian)
                let y = cal.component(.year, from: newValue)
                let m = cal.component(.month, from: newValue)
                let next = String(format: "%04d-%02d", y, m)
                if next != vm.month {
                    Task { await vm.changeMonth(next) }
                }
            }

            Button {
                // Haptic removed: 用户反馈月份切换按钮过密震动
                Task { await vm.shiftMonth(by: 1); syncMonthPickerDate() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .padding(8)
                    .background(Circle().fill(BsColor.brandAzure.opacity(0.1)))
                    .foregroundStyle(BsColor.brandAzure)
            }
            .accessibilityLabel("下一月")
        }
        .padding(.vertical, 6)
    }

    // ── Filters ─────────────────────────────────────────────────
    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !vm.departments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chipButton(title: "全部部门", isOn: vm.departmentFilter.isEmpty) {
                            vm.departmentFilter = ""
                        }
                        ForEach(vm.departments, id: \.self) { d in
                            chipButton(title: d, isOn: vm.departmentFilter == d) {
                                vm.departmentFilter = d
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            Picker("状态", selection: $vm.statusFilter) {
                ForEach(MonthlyEvaluationStatus.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            // Haptic removed: 用户反馈 picker 切换过密震动
        }
        .padding(.vertical, 6)
    }

    private func chipButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            // Haptic removed: 用户反馈 chip 切换过密震动
            action()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isOn ? BsColor.brandAzure : BsColor.brandAzure.opacity(0.08))
                )
                .foregroundStyle(isOn ? .white : BsColor.brandAzure)
        }
        .buttonStyle(.plain)
    }

    // ── Summary chips ───────────────────────────────────────────
    private var summaryChips: some View {
        let c = vm.counts
        return HStack(spacing: 8) {
            statChip(label: "总计", value: c.total, tint: BsColor.brandAzure)
            statChip(label: "待评", value: c.pending, tint: BsColor.inkMuted)
            statChip(label: "已评", value: c.evaluated, tint: BsColor.success)
            statChip(label: "需复核", value: c.needsReview, tint: BsColor.warning)
        }
        .padding(.vertical, 2)
    }

    private func statChip(label: String, value: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BsColor.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.08)))
    }

    // ── Row cell ────────────────────────────────────────────────
    @ViewBuilder
    private func rowCell(_ row: MonthlyMatrixRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            avatar(for: row)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BsColor.ink)
                        .lineLimit(1)
                    if row.primaryRole == "superadmin" {
                        Text("超管")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(BsColor.brandAzure.opacity(0.15)))  // TODO(batch-3): evaluate .purple → brandAzure
                            .foregroundStyle(BsColor.brandAzure)  // TODO(batch-3): evaluate .purple → brandAzure
                    } else if row.primaryRole == "admin" {
                        Text("管理")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(BsColor.brandAzure.opacity(0.15)))
                            .foregroundStyle(BsColor.brandAzure)
                    }
                }
                HStack(spacing: 6) {
                    Text(row.department ?? "未分部门")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                    Text("·")
                        .foregroundStyle(BsColor.inkFaint)
                    statusBadge(row: row)
                }
            }

            Spacer()

            overallScoreBadge(row: row)
        }
        .padding(.vertical, 4)
    }

    private func avatar(for row: MonthlyMatrixRow) -> some View {
        let initials = String(row.displayName.prefix(1))
        return ZStack {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.12))
                .frame(width: 40, height: 40)
            Text(initials)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BsColor.brandAzure)
        }
        .accessibilityLabel(row.displayName)
    }

    private func statusBadge(row: MonthlyMatrixRow) -> some View {
        let (label, color): (String, Color) = {
            guard let ev = row.evaluation else { return ("待评", BsColor.inkMuted) }
            if ev.requiresManualReview { return ("需复核", BsColor.warning) }
            if ev.triggeredBy == "cron" && ev.overallScore == nil { return ("自动失败", BsColor.danger) }
            return ("已评", BsColor.success)
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func overallScoreBadge(row: MonthlyMatrixRow) -> some View {
        let score = row.evaluation?.overallScore
        let text = score.map(String.init) ?? "—"
        let color: Color = {
            guard let s = score else { return BsColor.inkMuted }
            if s >= 90 { return BsColor.success }
            if s >= 80 { return BsColor.brandAzure }
            if s >= 60 { return BsColor.warning }
            if s >= 40 { return BsColor.warning.opacity(0.85) }
            return BsColor.danger
        }()
        return VStack(spacing: 0) {
            Text(text)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text("总分")
                .font(.caption2)
                .foregroundStyle(BsColor.inkFaint)
        }
        .frame(width: 56, height: 52)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.1)))
    }

    private func syncMonthPickerDate() {
        let parts = vm.month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        var comp = DateComponents()
        comp.year = parts[0]
        comp.month = parts[1]
        comp.day = 1
        if let d = Calendar(identifier: .gregorian).date(from: comp) {
            monthPickerDate = d
        }
    }
}
