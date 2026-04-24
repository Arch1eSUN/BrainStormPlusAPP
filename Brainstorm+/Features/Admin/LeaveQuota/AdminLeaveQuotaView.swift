import SwiftUI
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 4.6c — 调休额度矩阵主视图
// Web 是员工 × 月份宽表；iOS 压成按月 picker + 按部门分组的列表。
//   - 顶部：月份 DatePicker（年 + 月）+ 刷新
//   - 主区：按部门 Section 的 List，每行员工姓名 + 剩余/总额度
//   - Tap 行 → push AdminLeaveQuotaEditView
//   - Toolbar：批量设置 → AdminLeaveQuotaBatchSheet
// ══════════════════════════════════════════════════════════════════

public struct AdminLeaveQuotaView: View {
    @StateObject private var vm = AdminLeaveQuotaViewModel()
    @State private var showBatchSheet = false

    public init() {}

    public var body: some View {
        List {
            monthSection
            if vm.isLoading && vm.rows.isEmpty {
                Section {
                    ProgressView().frame(maxWidth: .infinity, alignment: .center)
                }
            } else if vm.rows.isEmpty {
                Section {
                    Text("暂无员工数据")
                        .foregroundStyle(BsColor.inkMuted)
                        .font(.subheadline)
                }
            } else {
                ForEach(vm.groupedRows, id: \.department) { group in
                    Section(group.department) {
                        ForEach(group.rows) { row in
                            NavigationLink {
                                AdminLeaveQuotaEditView(userId: row.userId)
                                    .environmentObject(vm)
                            } label: {
                                employeeRow(row)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("调休额度")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showBatchSheet = true
                } label: {
                    Label("批量设置", systemImage: "slider.horizontal.3")
                }
                .disabled(vm.rows.isEmpty)
            }
        }
        .sheet(isPresented: $showBatchSheet) {
            AdminLeaveQuotaBatchSheet()
                .environmentObject(vm)
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .zyErrorBanner($vm.errorMessage)
    }

    // ─── Month picker ───────────────────────────────────────────

    private var monthSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundStyle(BsColor.brandAzure)
                DatePicker(
                    "月份",
                    selection: Binding(
                        get: { AdminLeaveQuotaViewModel.date(fromYearMonth: vm.yearMonth) },
                        set: { newDate in
                            vm.yearMonth = AdminLeaveQuotaViewModel.yearMonth(from: newDate)
                            Task { await vm.load() }
                        }
                    ),
                    displayedComponents: [.date]
                )
                .labelsHidden()
            }
        } footer: {
            Text("默认每人每月 \(AdminLeaveQuotaViewModel.defaultTotalDays) 天，可按需覆盖。")
                .font(.caption)
                .foregroundStyle(BsColor.inkMuted)
        }
    }

    // ─── Employee row ───────────────────────────────────────────

    @ViewBuilder
    private func employeeRow(_ row: LeaveQuotaAdminRow) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(BsColor.brandAzure.opacity(0.12))
                    .frame(width: 34, height: 34)
                Text(initials(of: row.displayName))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BsColor.brandAzure)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.displayName)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BsColor.ink)
                Text("总额度 \(row.totalDays) · 已用 \(formatDays(row.usedDays)) · 返还 \(formatDays(row.revokedDays))")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("剩余")
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkMuted)
                Text(formatDays(row.availableDays))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(row.availableDays > 0 ? BsColor.success : BsColor.brandCoral)
            }
        }
        .padding(.vertical, 2)
    }

    private func initials(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "?" }
        // 中文：取最后一个字；英文：取首字母。
        if let scalar = trimmed.unicodeScalars.first, scalar.value > 0x2E80 {
            return String(trimmed.suffix(1))
        }
        return String(trimmed.prefix(1)).uppercased()
    }

    private func formatDays(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(v))
        }
        return String(format: "%.1f", v)
    }
}
