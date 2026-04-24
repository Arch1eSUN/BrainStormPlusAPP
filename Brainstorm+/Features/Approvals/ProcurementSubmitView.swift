import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Procurement submit form.
//
// 1:1 port of `src/components/approval/procurement-form.tsx`. Uses a
// Stepper for quantity, Decimal TextField for unit price, and a
// read-only computed total label underneath so the user sees what
// they're asking for.
//
// The `budgetAvailable` toggle reflects the Web form's "预算是否已
// 备妥" checkbox — when `false`, the request still goes through but
// flags to finance that funding isn't yet allocated. Server stores it
// as a boolean column; we forward the value as-is.
// ══════════════════════════════════════════════════════════════════

public struct ProcurementSubmitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ProcurementSubmitViewModel

    private let onSubmitted: (UUID) -> Void

    private static let selectablePriorities: [RequestPriority] = [
        .low, .medium, .high, .urgent
    ]

    public init(
        client: SupabaseClient,
        onSubmitted: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ProcurementSubmitViewModel(client: client))
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BsColor.pageBackground.ignoresSafeArea()
                Form {
                Section("采购项目") {
                    Picker("类型", selection: $viewModel.procurementType) {
                        ForEach(ProcurementType.allCases) { t in
                            Text(t.displayLabel).tag(t)
                        }
                    }
                    TextField("项目名称", text: $viewModel.itemDescription)
                    TextField("供应商", text: $viewModel.vendor)
                }

                Section("数量与单价") {
                    Stepper(value: $viewModel.quantity, in: 1...9_999) {
                        LabeledContent("数量", value: "\(viewModel.quantity)")
                    }

                    HStack {
                        TextField("单价", value: $viewModel.unitPriceYuan, format: .number)
                            .keyboardType(.decimalPad)
                        Text(viewModel.currency.isEmpty ? "CNY" : viewModel.currency)
                            .foregroundStyle(.secondary)
                    }

                    TextField("币种 (默认 CNY)", text: $viewModel.currency)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)

                    LabeledContent("合计", value: Self.formatYuan(viewModel.totalYuan))
                }

                Section("使用信息") {
                    TextField("使用人/使用部门", text: $viewModel.userOrDepartment)

                    TextField(
                        "采购用途",
                        text: $viewModel.purpose,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    TextField(
                        "采购理由（必填）",
                        text: $viewModel.justification,
                        axis: .vertical
                    )
                    .lineLimit(2...6)

                    TextField(
                        "替代方案（可选）",
                        text: $viewModel.alternatives,
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                }

                Section("预算与时间") {
                    Toggle("预算已备妥", isOn: $viewModel.budgetAvailable)

                    Toggle("指定期望采购日期", isOn: Binding(
                        get: { viewModel.expectedPurchaseDate != nil },
                        set: { enabled in
                            viewModel.expectedPurchaseDate = enabled ? Date() : nil
                        }
                    ))

                    if viewModel.expectedPurchaseDate != nil {
                        DatePicker(
                            "期望日期",
                            selection: Binding(
                                get: { viewModel.expectedPurchaseDate ?? Date() },
                                set: { viewModel.expectedPurchaseDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }

                Section("附加信息") {
                    TextField(
                        "业务事由（可选）",
                        text: $viewModel.businessReason,
                        axis: .vertical
                    )
                    .lineLimit(2...4)

                    TextField("关联项目（可选）", text: $viewModel.relatedProject)
                }

                Section("优先级") {
                    Picker("优先级", selection: $viewModel.priority) {
                        ForEach(Self.selectablePriorities, id: \.self) { p in
                            Text(priorityLabel(p)).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("采购申请")
            .navigationBarTitleDisplayMode(.inline)
            .zyErrorBanner($viewModel.errorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        Haptic.light()
                        dismiss()
                    }
                    .disabled(viewModel.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") {
                        Haptic.medium()
                        Task { await handleSubmit() }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .bsLoadingOverlay(isLoading: viewModel.isSubmitting, label: "提交中…")
            .onChange(of: viewModel.procurementType) { _, _ in Haptic.selection() }
            .onChange(of: viewModel.priority) { _, _ in Haptic.selection() }
            .onChange(of: viewModel.budgetAvailable) { _, _ in Haptic.light() }
        }
    }

    // MARK: - Helpers

    private func priorityLabel(_ p: RequestPriority) -> String {
        switch p {
        case .low:     return "低"
        case .medium:  return "中"
        case .high:    return "高"
        case .urgent:  return "紧急"
        case .unknown: return "未知"
        }
    }

    private static func formatYuan(_ yuan: Decimal) -> String {
        let n = NSDecimalNumber(decimal: yuan)
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 0
        fmt.maximumFractionDigits = 2
        return fmt.string(from: n) ?? "\(n)"
    }

    private func handleSubmit() async {
        let ok = await viewModel.submit()
        if ok, let id = viewModel.createdRequestId {
            Haptic.success()
            onSubmitted(id)
            dismiss()
        } else {
            Haptic.error()
        }
    }

}

#Preview {
    ProcurementSubmitView(client: supabase) { _ in }
}
