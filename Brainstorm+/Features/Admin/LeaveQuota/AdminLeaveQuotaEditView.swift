import SwiftUI
import Combine

// ══════════════════════════════════════════════════════════════════
// Phase 4.6c — 单员工单月份调休额度编辑
// Web 是行内 input + save/reset；iOS 拉成独立页面：
//   - 展示：姓名、部门、月份、已用、返还、剩余（计算值）
//   - 编辑：Stepper 调整 totalDays（0...31，Web 约束）
//   - 按钮：保存 / 重置为默认 4 天
// VM 通过 EnvironmentObject 注入；保存成功后 pop 回列表。
// ══════════════════════════════════════════════════════════════════

public struct AdminLeaveQuotaEditView: View {
    @EnvironmentObject private var vm: AdminLeaveQuotaViewModel
    @Environment(\.dismiss) private var dismiss

    let userId: UUID
    @State private var draftTotal: Int = AdminLeaveQuotaViewModel.defaultTotalDays
    @State private var didPrime = false

    public init(userId: UUID) {
        self.userId = userId
    }

    private var row: LeaveQuotaAdminRow? {
        vm.rows.first(where: { $0.userId == userId })
    }

    private var isSaving: Bool {
        vm.savingUserId == userId
    }

    private var isDirty: Bool {
        guard let row else { return false }
        return row.totalDays != draftTotal
    }

    private var previewAvailable: Double {
        guard let row else { return 0 }
        return max(0, Double(draftTotal) - row.usedDays + row.revokedDays)
    }

    public var body: some View {
        Group {
            if let row {
                Form {
                    Section("员工") {
                        LabeledContent("姓名", value: row.displayName)
                        LabeledContent("部门", value: row.displayDepartment)
                        LabeledContent("月份", value: row.yearMonth)
                    }

                    Section {
                        Stepper(
                            value: $draftTotal,
                            in: 0...31,
                            step: 1
                        ) {
                            HStack {
                                Text("总额度")
                                Spacer()
                                Text("\(draftTotal) 天")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isDirty ? BsColor.brandCoral : BsColor.ink)
                            }
                        }
                        LabeledContent("已使用", value: "\(formatDays(row.usedDays)) 天")
                        LabeledContent("已返还", value: "\(formatDays(row.revokedDays)) 天")
                        LabeledContent("剩余（预览）") {
                            Text("\(formatDays(previewAvailable)) 天")
                                .foregroundStyle(previewAvailable > 0 ? BsColor.success : BsColor.brandCoral)
                                .font(.subheadline.weight(.bold))
                        }
                    } header: {
                        Text("本月额度")
                    } footer: {
                        Text("剩余 = 总额度 − 已使用 + 已返还，最低 0。")
                            .font(.caption)
                            .foregroundStyle(BsColor.inkMuted)
                    }

                    Section {
                        Button {
                            Task { await handleSave() }
                        } label: {
                            HStack {
                                if isSaving {
                                    ProgressView().controlSize(.small)
                                }
                                Text("保存")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BsColor.brandAzure)
                        .disabled(!isDirty || isSaving)

                        Button(role: .destructive) {
                            Task { await handleReset() }
                        } label: {
                            Text("重置为默认（\(AdminLeaveQuotaViewModel.defaultTotalDays) 天）")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSaving || row.totalDays == AdminLeaveQuotaViewModel.defaultTotalDays)
                    }
                }
            } else {
                BsEmptyState(
                    title: "员工不存在",
                    systemImage: "person.slash",
                    description: "该员工可能已被移除，请返回列表刷新。"
                )
            }
        }
        .navigationTitle("编辑额度")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didPrime, let row else { return }
            draftTotal = row.totalDays
            didPrime = true
        }
        .zyErrorBanner($vm.errorMessage)
    }

    // ─── Actions ───────────────────────────────────────────────

    private func handleSave() async {
        let ok = await vm.setTotal(for: userId, totalDays: draftTotal)
        if ok { dismiss() }
    }

    private func handleReset() async {
        let ok = await vm.resetToDefault(for: userId)
        if ok {
            draftTotal = AdminLeaveQuotaViewModel.defaultTotalDays
            dismiss()
        }
    }

    private func formatDays(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(v))
        }
        return String(format: "%.1f", v)
    }
}
