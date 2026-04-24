import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Batch B.3 — Business trip submit form.
//
// No 1:1 Web source: Web's `/dashboard/approval/request` shell wires
// only leave / reimbursement / procurement / field_work. The business
// trip domain has existed server-side since Phase 2 (migration 045)
// but has never exposed a user-facing submission form on Web. iOS
// adds this form to round out the approver-queue story — approvers
// can already see business trips in the queue, so requesters should
// be able to create them from the same device.
//
// Form fields follow the `business_trip_requests` column set:
//   - 日期区间 (start_date / end_date)
//   - 出差地点 (destination)
//   - 出差事由 (purpose)
//   - 交通方式 (transportation — optional enum)
//   - 预计费用 (estimated_cost — optional yuan, NUMERIC(10,2))
//
// When Web eventually ships its own business-trip form + RPC, this
// view should migrate to the RPC for trust-boundary parity (see
// BusinessTripSubmitViewModel header). Until then the direct insert
// is safe because RLS enforces user_id=auth.uid() + status defaults
// 'pending' + approved_by requires a privileged role.
// ══════════════════════════════════════════════════════════════════

public struct BusinessTripSubmitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BusinessTripSubmitViewModel

    private let onSubmitted: (UUID) -> Void

    private static let selectableTransportation: [BusinessTripTransportation] = [
        .flight, .train, .car, .other
    ]

    public init(
        client: SupabaseClient,
        onSubmitted: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: BusinessTripSubmitViewModel(client: client))
        self.onSubmitted = onSubmitted
    }

    /// Batch C.3 — quick-apply overload used by the schedule "my" view.
    /// Pre-fills both `startDate` and `endDate` with the tapped row's date.
    public init(
        client: SupabaseClient,
        initialDate: Date,
        onSubmitted: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: BusinessTripSubmitViewModel(client: client, initialDate: initialDate)
        )
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BsColor.pageBackground.ignoresSafeArea()
                Form {
                Section("日期") {
                    DatePicker(
                        "开始日期",
                        selection: $viewModel.startDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "结束日期",
                        selection: $viewModel.endDate,
                        in: viewModel.startDate...,
                        displayedComponents: .date
                    )
                }

                Section("目的地 / 事由") {
                    TextField("出差地点", text: $viewModel.destination)
                    TextField(
                        "出差事由",
                        text: $viewModel.purpose,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                }

                Section("交通方式") {
                    Picker("交通方式", selection: $viewModel.transportation) {
                        Text("不填").tag(Optional<BusinessTripTransportation>.none)
                        ForEach(Self.selectableTransportation, id: \.self) { t in
                            Text(t.displayLabel).tag(Optional(t))
                        }
                    }
                }

                Section {
                    TextField(
                        "预计费用（元）",
                        text: $viewModel.estimatedCost
                    )
                    .keyboardType(.decimalPad)
                } header: {
                    Text("费用")
                } footer: {
                    Text("费用以元为单位，最多保留 2 位小数。选填。")
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkMuted)
                }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("出差申请")
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
            .onChange(of: viewModel.transportation) { _, _ in Haptic.selection() }
        }
    }

    // MARK: - Helpers

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
    BusinessTripSubmitView(client: supabase) { _ in }
}
