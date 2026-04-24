import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Field-work submit form.
//
// 1:1 port of `src/components/approval/field-work-form.tsx`. The
// DatePicker's `in:` range starts at tomorrow (UTC) to mirror the
// server's "必须至少提前一天提交" rule. The VM also rejects server-
// side via RPC RAISE EXCEPTION.
//
// `expectedReturn` is a free-form text (e.g. "17:30" or "当日返回")
// because the Web form accepts the same shape and some field-work
// trips don't have a clean return time.
// ══════════════════════════════════════════════════════════════════

public struct FieldWorkSubmitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FieldWorkSubmitViewModel

    private let onSubmitted: (UUID) -> Void

    public init(
        client: SupabaseClient,
        onSubmitted: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: FieldWorkSubmitViewModel(client: client))
        self.onSubmitted = onSubmitted
    }

    /// Batch C.3 — quick-apply overload. If `initialDate` is earlier than
    /// tomorrow (the server's "at least 1 day ahead" rule), the VM keeps
    /// the default tomorrow anchor to avoid landing the user in an
    /// immediately-invalid state.
    public init(
        client: SupabaseClient,
        initialDate: Date,
        onSubmitted: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: FieldWorkSubmitViewModel(client: client, initialDate: initialDate)
        )
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BsColor.pageBackground.ignoresSafeArea()
                Form {
                Section("外勤信息") {
                    DatePicker(
                        "外勤日期",
                        selection: $viewModel.targetDate,
                        in: Self.tomorrowUTC...,
                        displayedComponents: .date
                    )

                    TextField("外勤地点", text: $viewModel.location)

                    TextField("预计返回时间 (可选)", text: $viewModel.expectedReturn)
                }

                Section {
                    TextField(
                        "外勤事由",
                        text: $viewModel.reason,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                } header: {
                    Text("事由")
                } footer: {
                    Text("外勤申请需至少提前一天提交。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("外勤申请")
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
        }
    }

    // MARK: - Helpers

    private static var tomorrowUTC: Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let today = cal.startOfDay(for: Date())
        return cal.date(byAdding: .day, value: 1, to: today) ?? today
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
    FieldWorkSubmitView(client: supabase) { _ in }
}
