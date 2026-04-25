import SwiftUI
import Combine
import PhotosUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// AttendanceCorrectionSubmitSheet
//
// 用户从考勤 timeline 长按弹出的"申请补卡 / 异常修正"表单。落表
// `public.attendance_corrections` (见 migration 20260426000000),
// 提交后等管理员在 Web 端审批,审批通过后 attendance_records 由独立
// worker 回写(见 RPC 注释)。
//
// UX 设计参考 LeaveSubmitView 的 Form 布局,字段顺序对齐 RPC 入参,
// 减少 Web/iOS 表单互译成本。
// ══════════════════════════════════════════════════════════════════

public struct AttendanceCorrectionSubmitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: AttendanceCorrectionSubmitViewModel

    /// Caller passes the day-row that triggered this sheet so we can
    /// pre-fill `target_date` and (when the row already had punches)
    /// the proposed clock times.
    public init(
        client: SupabaseClient = supabase,
        seed: AttendanceDay,
        onSubmitted: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(
            wrappedValue: AttendanceCorrectionSubmitViewModel(
                client: client,
                seed: seed,
                onSubmitted: onSubmitted
            )
        )
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("修正日期") {
                    DatePicker(
                        "目标日期",
                        selection: $viewModel.targetDate,
                        displayedComponents: .date
                    )
                }

                Section("修正类型") {
                    Picker("类型", selection: $viewModel.correctionType) {
                        ForEach(AttendanceCorrectionType.allCases) { t in
                            Text(t.displayLabel).tag(t)
                        }
                    }
                }

                if viewModel.correctionType.requiresClockIn {
                    Section("主张上班时间") {
                        DatePicker(
                            "上班",
                            selection: $viewModel.proposedClockIn,
                            displayedComponents: [.hourAndMinute]
                        )
                    }
                }

                if viewModel.correctionType.requiresClockOut {
                    Section("主张下班时间") {
                        DatePicker(
                            "下班",
                            selection: $viewModel.proposedClockOut,
                            displayedComponents: [.hourAndMinute]
                        )
                    }
                }

                Section {
                    TextField(
                        "请说明本次补卡 / 修正的原因(至少 10 字)",
                        text: $viewModel.reason,
                        axis: .vertical
                    )
                    .lineLimit(4...10)
                } header: {
                    Text("说明")
                } footer: {
                    Text("\(viewModel.reason.count) / 200")
                        .font(.caption2)
                        .foregroundStyle(
                            viewModel.reason.count >= 10
                            ? BsColor.inkMuted : BsColor.warning
                        )
                }

                Section {
                    PhotosPicker(
                        selection: $viewModel.evidencePicks,
                        maxSelectionCount: 3,
                        matching: .images
                    ) {
                        Label(
                            viewModel.evidenceUrls.isEmpty
                            ? "添加证据图(可选,最多 3 张)"
                            : "已选 \(viewModel.evidenceUrls.count) 张,可继续添加",
                            systemImage: "photo.on.rectangle"
                        )
                    }

                    if !viewModel.evidenceUrls.isEmpty {
                        ForEach(Array(viewModel.evidenceUrls.enumerated()), id: \.offset) { idx, url in
                            HStack(spacing: BsSpacing.sm) {
                                Image(systemName: "paperclip")
                                    .foregroundStyle(BsColor.success)
                                Text(URL(string: url)?.lastPathComponent ?? "附件 \(idx + 1)")
                                    .font(BsTypography.caption)
                                    .foregroundStyle(BsColor.inkMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button(role: .destructive) {
                                    viewModel.removeEvidence(at: idx)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(BsColor.danger)
                            }
                        }
                    }
                } header: {
                    Text("证据")
                } footer: {
                    Text("支持 JPG / PNG。补卡通常需要工卡 / 钉钉截图等佐证。")
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkFaint)
                }
            }
            .scrollContentBackground(.hidden)
            .background(BsColor.pageBackground.ignoresSafeArea())
            .navigationTitle("申请补卡 / 异常修正")
            .bsModalNavBar(displayMode: .inline)
            .zyErrorBanner($viewModel.errorMessage)
            .bsLoadingOverlay(isLoading: viewModel.isSubmitting, label: "提交中…")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") {
                        Haptic.medium()
                        Task { await handleSubmit() }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .onChange(of: viewModel.evidencePicks) { _, _ in
                Task { await viewModel.processEvidencePicks() }
            }
        }
    }

    private func handleSubmit() async {
        let ok = await viewModel.submit()
        if ok {
            Haptic.success()
            dismiss()
        } else {
            Haptic.error()
        }
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - AttendanceCorrectionType
// ══════════════════════════════════════════════════════════════════

public enum AttendanceCorrectionType: String, CaseIterable, Identifiable, Hashable {
    case missedClockIn      = "missed_clock_in"
    case missedClockOut     = "missed_clock_out"
    case lateExcuse         = "late_excuse"
    case earlyLeaveExcuse   = "early_leave_excuse"
    case wrongRecord        = "wrong_record"

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .missedClockIn:    return "漏打上班卡"
        case .missedClockOut:   return "漏打下班卡"
        case .lateExcuse:       return "迟到说明"
        case .earlyLeaveExcuse: return "早退说明"
        case .wrongRecord:      return "记录错误"
        }
    }

    /// Whether the form should expose the proposed clock-in picker.
    public var requiresClockIn: Bool {
        switch self {
        case .missedClockIn, .wrongRecord, .lateExcuse: return true
        default: return false
        }
    }

    /// Whether the form should expose the proposed clock-out picker.
    public var requiresClockOut: Bool {
        switch self {
        case .missedClockOut, .wrongRecord, .earlyLeaveExcuse: return true
        default: return false
        }
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - ViewModel
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class AttendanceCorrectionSubmitViewModel: ObservableObject {
    @Published public var targetDate: Date
    @Published public var correctionType: AttendanceCorrectionType
    @Published public var proposedClockIn: Date
    @Published public var proposedClockOut: Date
    @Published public var reason: String = ""

    @Published public var evidencePicks: [PhotosPickerItem] = []
    @Published public private(set) var evidenceUrls: [String] = []

    @Published public private(set) var isSubmitting: Bool = false
    @Published public var errorMessage: String?

    private let client: SupabaseClient
    private let onSubmitted: () -> Void

    public init(
        client: SupabaseClient,
        seed: AttendanceDay,
        onSubmitted: @escaping () -> Void
    ) {
        self.client = client
        self.onSubmitted = onSubmitted
        self.targetDate = seed.date

        // Default correction type by what the row was missing.
        if seed.clockIn == nil {
            self.correctionType = .missedClockIn
        } else if seed.clockOut == nil {
            self.correctionType = .missedClockOut
        } else if seed.status == .late {
            self.correctionType = .lateExcuse
        } else if seed.status == .earlyLeave {
            self.correctionType = .earlyLeaveExcuse
        } else {
            self.correctionType = .wrongRecord
        }

        // Pre-fill proposed times from existing punches when present;
        // otherwise default to a sensible 09:00/18:00 on target date.
        let cal = Calendar(identifier: .gregorian)
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: seed.date) ?? seed.date
        let six  = cal.date(bySettingHour: 18, minute: 0, second: 0, of: seed.date) ?? seed.date
        self.proposedClockIn  = seed.clockIn  ?? nine
        self.proposedClockOut = seed.clockOut ?? six
    }

    public var canSubmit: Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 10 && !isSubmitting
    }

    // MARK: - Evidence

    public func processEvidencePicks() async {
        guard !evidencePicks.isEmpty else { return }
        // Only process net-new picks. Once converted into a URL, drop
        // from the picker queue so re-renders don't re-upload.
        let toProcess = evidencePicks
        evidencePicks = []

        for item in toProcess {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }
                // Reuse the medical-cert helper —— same bucket
                // (`approval_attachments`), same RLS shape (first folder =
                // auth.uid()),只是子目录用 `medical_cert/` 命名了,Storage
                // console 能看出来是补卡证据无所谓。
                let url = try await LeaveStorageClient.uploadMedicalCert(
                    data: data,
                    fileName: "correction-\(UUID().uuidString.prefix(8)).jpg",
                    mimeType: "image/jpeg",
                    client: client
                )
                if evidenceUrls.count < 3 {
                    evidenceUrls.append(url)
                }
            } catch {
                errorMessage = "上传失败: \(ErrorLocalizer.localize(error))"
            }
        }
    }

    public func removeEvidence(at idx: Int) {
        guard evidenceUrls.indices.contains(idx) else { return }
        evidenceUrls.remove(at: idx)
    }

    // MARK: - Submit

    public func submit() async -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else {
            errorMessage = "说明至少需要 10 字"
            return false
        }
        guard let userId = (try? await client.auth.session.user.id) else {
            errorMessage = "未登录"
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil

        let row = AttendanceCorrectionInsert(
            userId: userId,
            targetDate: Self.yyyyMMdd.string(from: targetDate),
            correctionType: correctionType.rawValue,
            proposedClockIn: correctionType.requiresClockIn ? proposedClockIn : nil,
            proposedClockOut: correctionType.requiresClockOut ? proposedClockOut : nil,
            reason: trimmed,
            evidenceUrls: evidenceUrls.isEmpty ? nil : evidenceUrls
        )

        do {
            try await client
                .from("attendance_corrections")
                .insert(row)
                .execute()
            onSubmitted()
            return true
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            return false
        }
    }

    // MARK: - Encoding helpers

    private static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()
}

// MARK: - Insert payload

private struct AttendanceCorrectionInsert: Encodable {
    let userId: UUID
    let targetDate: String
    let correctionType: String
    let proposedClockIn: Date?
    let proposedClockOut: Date?
    let reason: String
    let evidenceUrls: [String]?

    enum CodingKeys: String, CodingKey {
        case userId           = "user_id"
        case targetDate       = "target_date"
        case correctionType   = "correction_type"
        case proposedClockIn  = "proposed_clock_in"
        case proposedClockOut = "proposed_clock_out"
        case reason
        case evidenceUrls     = "evidence_urls"
    }
}
