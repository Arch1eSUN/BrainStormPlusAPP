import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
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
//
// ───────────────────────────────────────────────────────────────────
// Batch B.3 additions — half-day picker + sick-leave medical cert
//
// Half-day UI surfaces a Toggle that, when on, hides the end date
// picker (half-day is always same-day) and swaps in a segmented
// control for 4h / 8h plus a custom-hours TextField. The VM
// auto-converts hours → fractional days before calling the RPC
// (which still only accepts `p_days`). See VM header for rationale.
//
// Medical cert uploader (已接入 Storage) appears only when leaveType
// == .sick. It surfaces:
//   - A softer "建议附上医疗证明" note for sick leave < 3 days
//   - A stronger "需要上传医疗证明" note for sick leave ≥ 3 days
//     (matching the server's auto-compute of medical_cert_required)
// The uploader itself is PhotosPicker + `.fileImporter([.pdf,
// .image])`, mutually exclusive with a "已上传 1 个附件" row + 删除
// button once a URL is set. Upload hits `LeaveStorageClient` → bucket
// `approval_attachments` (shared with reimbursement receipts). The
// URL is attached to the detail row via a post-submit UPDATE — see
// `LeaveSubmitViewModel.attachMedicalCertURL`.
// ══════════════════════════════════════════════════════════════════

public struct LeaveSubmitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LeaveSubmitViewModel

    /// Called with the created request's UUID after a successful
    /// submission. Parent typically refreshes the "我提交的" list.
    private let onSubmitted: (UUID) -> Void

    // Local UI state for the medical-cert uploader. Kept in the view
    // (not the VM) for the same reason the reimbursement form does it
    // — PhotosPicker / fileImporter bindings are SwiftUI-framework-
    // coupled and the VM stays `import UIKit`-free. Single-slot array
    // binding for PhotosPicker; `showFileImporter` toggles the sheet.
    @State private var photoItem: PhotosPickerItem?
    @State private var showCertFileImporter: Bool = false

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

    /// Batch C.3 — convenience overload used by the schedule "my" view's
    /// quick-apply entries: pre-fills `startDate` and `endDate` with the
    /// tapped row's date so the user only picks a type + reason.
    public init(
        client: SupabaseClient,
        initialDate: Date,
        onSubmitted: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: LeaveSubmitViewModel(client: client, initialDate: initialDate)
        )
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BsColor.pageBackground.ignoresSafeArea()
                Form {
                Section("请假类型") {
                    Picker("类型", selection: $viewModel.leaveType) {
                        ForEach(Self.selectableLeaveTypes, id: \.self) { t in
                            Text(t.displayLabel).tag(t)
                        }
                    }
                }

                // Batch B.3 — half-day toggle
                Section {
                    Toggle("按小时请假（半天/整天）", isOn: $viewModel.isHalfDay.animation())

                    if viewModel.isHalfDay {
                        Picker("时长", selection: $viewModel.presetHours) {
                            Text("4 小时（半天）").tag(4.0)
                            Text("8 小时（整天）").tag(8.0)
                        }
                        .pickerStyle(.segmented)

                        TextField(
                            "自定义小时数（可选）",
                            text: $viewModel.customHours
                        )
                        .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("时长模式")
                } footer: {
                    if viewModel.isHalfDay {
                        Text("按小时请假时，天数 = 小时 / 8。例如 4 小时 = 0.5 天。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("日期") {
                    DatePicker(
                        "开始日期",
                        selection: $viewModel.startDate,
                        displayedComponents: .date
                    )
                    if !viewModel.isHalfDay {
                        DatePicker(
                            "结束日期",
                            selection: $viewModel.endDate,
                            in: viewModel.startDate...,
                            displayedComponents: .date
                        )
                    }
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

                // Sick-leave medical cert uploader
                if viewModel.shouldShowMedicalCertHint {
                    Section {
                        medicalCertUploader
                    } header: {
                        Text("医疗证明（选填）")
                    } footer: {
                        VStack(alignment: .leading, spacing: 4) {
                            if viewModel.requiresMedicalCert {
                                Label(
                                    "病假 3 天及以上需要上传医疗证明。",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            } else {
                                Label(
                                    "建议附上医疗证明以加快审批。",
                                    systemImage: "info.circle"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            Text("支持 JPG / PNG / PDF。上传一个文件即可。")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("请假申请")
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
            .onChange(of: viewModel.leaveType) { _, _ in Haptic.selection() }
            .onChange(of: viewModel.priority) { _, _ in Haptic.selection() }
            .onChange(of: viewModel.isHalfDay) { _, _ in Haptic.light() }
            .onChange(of: photoItem) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    await viewModel.uploadMedicalCert(item: item)
                    photoItem = nil
                }
            }
            .fileImporter(
                isPresented: $showCertFileImporter,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                Task { await handlePickedCertFile(result) }
            }
        }
    }

    // MARK: - Medical cert uploader

    @ViewBuilder
    private var medicalCertUploader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.medicalCertUrl == nil {
                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $photoItem,
                        matching: .images
                    ) {
                        Label("从相册选择", systemImage: "photo.on.rectangle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                            .foregroundStyle(Color.accentColor)
                    }
                    .disabled(viewModel.isUploadingCert)

                    Button {
                        showCertFileImporter = true
                    } label: {
                        Label("选择文件", systemImage: "doc.badge.plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isUploadingCert)

                    Spacer()

                    if viewModel.isUploadingCert {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("上传中…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已上传 1 个附件")
                            .font(.subheadline.weight(.medium))
                        if let name = viewModel.medicalCertFileName {
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Haptic.rigid()
                        viewModel.clearMedicalCert()
                    } label: {
                        Text("删除")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// `.fileImporter` result handler. Walks the one returned URL,
    /// reads bytes under security-scoped access, delegates to the VM.
    private func handlePickedCertFile(_ result: Result<[URL], Error>) async {
        let urls: [URL]
        switch result {
        case .success(let picked):
            urls = picked
        case .failure(let error):
            viewModel.errorMessage = "选择文件失败: \(ErrorLocalizer.localize(error))"
            return
        }
        guard let url = urls.first else { return }

        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            viewModel.errorMessage = "未能读取所选文件"
            return
        }
        await viewModel.uploadMedicalCert(data: data, fileName: url.lastPathComponent)
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
            Haptic.success()
            onSubmitted(id)
            dismiss()
        } else {
            Haptic.error()
        }
    }

}

#Preview {
    LeaveSubmitView(client: supabase) { _ in }
}
