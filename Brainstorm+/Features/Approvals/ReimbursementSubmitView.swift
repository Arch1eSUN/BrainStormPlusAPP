import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Reimbursement submit form.
//
// 1:1 port of `src/components/approval/reimbursement-form.tsx`.
//
// Money input: we use `TextField(value: $amountYuan, format: .number)`
// which binds a `Decimal` directly — avoids the `String → Double →
// round` dance that would let 19.99 get serialized as 19.990000004.
// The form shows yuan; the VM converts to cents on submit.
//
// Attachments + receipt URLs: form surface deferred (4.x polish). The
// VM's default empty arrays flow through fine.
// ══════════════════════════════════════════════════════════════════

public struct ReimbursementSubmitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ReimbursementSubmitViewModel

    private let onSubmitted: (UUID) -> Void

    private static let selectablePriorities: [RequestPriority] = [
        .low, .medium, .high, .urgent
    ]

    public init(
        client: SupabaseClient,
        onSubmitted: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ReimbursementSubmitViewModel(client: client))
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("报销项目") {
                    TextField("项目名称", text: $viewModel.itemDescription)

                    Picker("类别", selection: $viewModel.category) {
                        ForEach(ReimbursementCategory.allCases) { c in
                            Text(c.displayLabel).tag(c)
                        }
                    }

                    DatePicker(
                        "购买/发生日期",
                        selection: $viewModel.purchaseDate,
                        displayedComponents: .date
                    )
                }

                Section("金额") {
                    HStack {
                        TextField("金额", value: $viewModel.amountYuan, format: .number)
                            .keyboardType(.decimalPad)
                        Text(viewModel.currency.isEmpty ? "CNY" : viewModel.currency)
                            .foregroundStyle(.secondary)
                    }
                    TextField("币种 (默认 CNY)", text: $viewModel.currency)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }

                Section("商户与支付") {
                    TextField("商户/收款方", text: $viewModel.merchant)

                    Picker("支付方式", selection: $viewModel.paymentMethod) {
                        ForEach(PaymentMethod.allCases) { m in
                            Text(m.displayLabel).tag(m)
                        }
                    }
                }

                Section("用途说明") {
                    TextField(
                        "请说明该笔费用的用途",
                        text: $viewModel.purpose,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
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
            .navigationTitle("报销申请")
            .navigationBarTitleDisplayMode(.inline)
            .zyErrorBanner($viewModel.errorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(viewModel.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") {
                        Task { await handleSubmit() }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .overlay {
                if viewModel.isSubmitting {
                    submittingOverlay
                }
            }
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

    private func handleSubmit() async {
        let ok = await viewModel.submit()
        if ok, let id = viewModel.createdRequestId {
            onSubmitted(id)
            dismiss()
        }
    }

    private var submittingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            ProgressView("提交中…")
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
        }
    }
}

#Preview {
    ReimbursementSubmitView(client: supabase) { _ in }
}
