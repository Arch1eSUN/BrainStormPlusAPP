import SwiftUI
import Combine

// ══════════════════════════════════════════════════════════════════
// Phase 4.6c — 批量设置调休额度 Sheet
// Web 原页面没有批量操作（只支持单行保存 + 重置）。iOS 在手机窄屏下
// 逐个 tap 效率低，按任务书要求补一个批量 sheet：
//   - 范围：整个部门 / 手选员工
//   - 输入：统一 total_days（Stepper 0...31）
//   - 应用：串行 upsert 每个目标 user（VM.applyBatch），逐个报错
// 不改后端合约；纯客户端循环 adminSetCompTimeQuotaTotal 等价操作。
// ══════════════════════════════════════════════════════════════════

public struct AdminLeaveQuotaBatchSheet: View {
    @EnvironmentObject private var vm: AdminLeaveQuotaViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Scope: Hashable {
        case department
        case individuals
    }

    @State private var scope: Scope = .department
    @State private var selectedDepartment: String = ""
    @State private var selectedUserIds: Set<UUID> = []
    @State private var totalDays: Int = AdminLeaveQuotaViewModel.defaultTotalDays
    @State private var isApplying: Bool = false
    @State private var lastResult: (ok: Int, failed: Int)?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                scopeSection
                targetSection
                valueSection
                if let r = lastResult {
                    Section {
                        Text("已应用：成功 \(r.ok) 人，失败 \(r.failed) 人")
                            .font(.caption)
                            .foregroundStyle(r.failed == 0 ? BsColor.success : BsColor.brandCoral)
                    }
                }
            }
            .navigationTitle("批量设置额度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .disabled(isApplying)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await apply() }
                    } label: {
                        if isApplying {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("应用")
                        }
                    }
                    .disabled(!canApply || isApplying)
                }
            }
            .onAppear {
                if selectedDepartment.isEmpty {
                    selectedDepartment = vm.allDepartments.first ?? ""
                }
            }
            .zyErrorBanner($vm.errorMessage)
        }
    }

    // ─── Sections ──────────────────────────────────────────────

    private var scopeSection: some View {
        Section("范围") {
            Picker("范围", selection: $scope) {
                Text("按部门").tag(Scope.department)
                Text("手选员工").tag(Scope.individuals)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        switch scope {
        case .department:
            Section("选择部门") {
                if vm.allDepartments.isEmpty {
                    Text("暂无部门").foregroundStyle(BsColor.inkMuted).font(.subheadline)
                } else {
                    Picker("部门", selection: $selectedDepartment) {
                        ForEach(vm.allDepartments, id: \.self) { d in
                            Text(d).tag(d)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Text("将影响 \(departmentUserIds.count) 名员工")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
        case .individuals:
            Section("选择员工") {
                if vm.rows.isEmpty {
                    Text("暂无员工").foregroundStyle(BsColor.inkMuted).font(.subheadline)
                } else {
                    ForEach(vm.rows) { row in
                        Button {
                            toggle(userId: row.userId)
                        } label: {
                            HStack {
                                Image(systemName: selectedUserIds.contains(row.userId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedUserIds.contains(row.userId) ? BsColor.brandAzure : BsColor.inkMuted)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(BsColor.ink)
                                    Text(row.displayDepartment)
                                        .font(.caption)
                                        .foregroundStyle(BsColor.inkMuted)
                                }
                                Spacer()
                                Text("\(row.totalDays) 天")
                                    .font(.caption)
                                    .foregroundStyle(BsColor.inkMuted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("已选 \(selectedUserIds.count) 人")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
        }
    }

    private var valueSection: some View {
        Section("统一额度") {
            Stepper(value: $totalDays, in: 0...31, step: 1) {
                HStack {
                    Text("总额度")
                    Spacer()
                    Text("\(totalDays) 天")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BsColor.ink)
                }
            }
            Text("月份：\(vm.yearMonth)")
                .font(.caption)
                .foregroundStyle(BsColor.inkMuted)
        }
    }

    // ─── Target resolution ─────────────────────────────────────

    private var departmentUserIds: [UUID] {
        vm.userIds(inDepartment: selectedDepartment)
    }

    private var targetIds: [UUID] {
        switch scope {
        case .department:
            return departmentUserIds
        case .individuals:
            return vm.rows.map(\.userId).filter { selectedUserIds.contains($0) }
        }
    }

    private var canApply: Bool {
        !targetIds.isEmpty
    }

    private func toggle(userId: UUID) {
        if selectedUserIds.contains(userId) {
            selectedUserIds.remove(userId)
        } else {
            selectedUserIds.insert(userId)
        }
    }

    // ─── Action ────────────────────────────────────────────────

    private func apply() async {
        isApplying = true
        defer { isApplying = false }
        let result = await vm.applyBatch(to: targetIds, totalDays: totalDays)
        lastResult = result
        if result.failed == 0 {
            dismiss()
        }
    }
}
