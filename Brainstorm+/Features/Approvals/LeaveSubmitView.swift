import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Leave submit form.
//
// 1:1 port of `src/components/approval/leave-form.tsx`. Field order
// mirrors the Web form (type → date range → priority → reason) so a
// user who submitted on Web yesterday doesn't feel lost on iOS.
//
// Quota check: the VM calls the RPC which internally does the
// per-month comp_time quota pre-check. On insufficient balance the
// RPC raises "调休额度不足：..." and the banner shows it. We don't
// pre-fetch quota in the form — it'd be a second round-trip for a
// very rare sad-path.
//
// `LeaveType` and `RequestPriority` are not `CaseIterable` (they both
// carry an `unknown` escape-hatch case for forgiving decoding that
// shouldn't show up in a user-facing Picker). We list the selectable
// cases inline here.
// ══════════════════════════════════════════════════════════════════

public struct LeaveSubmitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LeaveSubmitViewModel

    /// Called with the created request's UUID after a successful
    /// submission. Parent typically refreshes the "我提交的" list.
    private let onSubmitted: (UUID) -> Void

    private static let selectableLeaveTypes: [LeaveType] = [
        .annual, .sick, .personal, .compTime,
        .maternity, .paternity, .bereavement, .other
    ]

    private static let selectablePriorities: [RequestPriority] = [
        .low, .medium, .high, .urgent
    ]

    public init(
        client: SupabaseClient,
        onSubmitted: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: LeaveSubmitViewModel(client: client))
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("请假类型") {
                    Picker("类型", selection: $viewModel.leaveType) {
                        ForEach(Self.selectableLeaveTypes, id: \.self) { t in
                            Text(t.displayLabel).tag(t)
                        }
                    }
                }

                Section("日期") {
                    DatePicker("开始日期", selection: $viewModel.startDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $viewModel.endDate, in: viewModel.startDate..., displayedComponents: .date)
                    LabeledContent("天数", value: String(format: "%g 天", viewModel.days))
                }

                Section("优先级") {
                    Picker("优先级", selection: $viewModel.priority) {
                        ForEach(Self.selectablePriorities, id: \.self) { p in
                            Text(priorityLabel(p)).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("事由") {
                    TextField(
                        "请说明请假事由",
                        text: $viewModel.reason,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                }
            }
            .navigationTitle("请假申请")
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
    LeaveSubmitView(client: supabase) { _ in }
}
