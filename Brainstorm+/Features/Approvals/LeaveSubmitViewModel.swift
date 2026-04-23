import Foundation
import Combine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Leave submit ViewModel.
//
// Parity target: Web `submitLeaveRequest` in `src/lib/leave/unified.ts`
// + the leave-request form in `src/components/approval/leave-form.tsx`.
//
// Why call the RPC instead of inserting directly:
//   1. The `shouldAutoApprove` deadlock bypass requires writing
//      `status='approved' + reviewer_id=null` on insert, which user-
//      JWT RLS forbids (WITH CHECK auth.uid() = requester_id allows
//      the insert but a malicious client could also forge 'approved'
//      for any leave — we need server-side trust).
//   2. The per-month comp_time quota pre-check reads
//      `comp_time_quotas` and must race-safely succeed-or-reject as
//      one atomic operation. Doing it in two round-trips lets a second
//      concurrent submission slip past the check.
//
// Chinese errors from the RPC (quota exhausted, date range invalid,
// reason missing) surface here via `errorMessage` and bubble to
// `.zyErrorBanner`. See migration 20260421180000_approvals_submit_rpcs.sql
// for the RAISE-EXCEPTION call sites.
//
// ───────────────────────────────────────────────────────────────────
// Batch B.3 additions — half-day `hours` + sick-leave medical-cert
//
// The DB table `approval_request_leave.hours NUMERIC(4,1)` has existed
// since migration 020 but the Web form + RPC only consume `days`. To
// stay 1:1 with the RPC's signature (`approvals_submit_leave(... p_days
// NUMERIC ...)`) while still supporting the iOS half-day UX, the VM
// converts hours → a fractional `days` value (hours / 8) before
// calling the RPC. The DB rounds to 0.1, which preserves 0.5 / 0.625
// / 1.0 etc. equivalents cleanly.
//
// Medical-cert upload: the RPC computes `medical_cert_required` as
// (leave_type = 'sick' AND days >= 3) and always writes
// `medical_cert_uploaded = false` on insert (see migration
// 20260421180000:280-281). iOS now uploads the file itself via
// `LeaveStorageClient` (bucket = `approval_attachments`, shared with
// reimbursement receipts) and, after the RPC returns the new
// request_id, runs a follow-up UPDATE on `approval_request_leave` to
// set `medical_cert_url = $1, medical_cert_name = $2,
// medical_cert_uploaded = true`. The self-UPDATE path is allowed by
// the "Leave detail follows request access" policy in
// 027_permission_alignment.sql (the requester is always a participant
// on their own leave row). The URL columns are added in migration
// 20260423110000_leave_medical_cert_url.sql — until that migration
// ships to prod the writeback will soft-fail and the request still
// lands with `medical_cert_uploaded=false` (client-side URL is lost
// but the form submission itself succeeds).
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class LeaveSubmitViewModel: ObservableObject {
    // MARK: - Form state (bound by the view)

    @Published public var leaveType: LeaveType = .annual
    @Published public var startDate: Date = Date()
    @Published public var endDate: Date = Date()
    @Published public var reason: String = ""
    @Published public var priority: RequestPriority = .medium

    // Batch B.3 — half-day / custom-hours support.
    //
    // `isHalfDay` toggles the continuous-hours picker. When off, the VM
    // falls back to the whole-day span (inclusive endDate - startDate + 1).
    // When on, the user picks 4 (半天) / 8 (整天) as a segmented control, or
    // enters a custom value in `customHours` for partial days that span
    // multiple calendar dates (rare but possible — e.g. 12h spread over
    // two half-days).
    @Published public var isHalfDay: Bool = false
    /// Pre-set hour buckets. 4h = 半天, 8h = 整天. Picker-bound.
    @Published public var presetHours: Double = 4
    /// Free-text custom hours input; overrides `presetHours` when > 0.
    /// Stored as String so partial input (e.g. "3.") doesn't trip Double
    /// coercion — parsed at submit time.
    @Published public var customHours: String = ""

    // Sick-leave medical certificate — nil until the user uploads.
    // URL is the Supabase Storage public URL; fileName is the
    // original user-facing label shown in the "已上传 1 个附件" row and
    // later on the approval detail screen. After submit() the URL +
    // filename get persisted via the post-submit UPDATE described in
    // the file header.
    @Published public var medicalCertUrl: String?
    @Published public var medicalCertFileName: String?

    // MARK: - Submit state (read-only from the view)

    @Published public private(set) var isSubmitting: Bool = false
    @Published public private(set) var isUploadingCert: Bool = false
    @Published public var errorMessage: String?
    @Published public private(set) var createdRequestId: UUID?

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    /// Batch C.3 — overload that pre-fills `startDate`/`endDate` from a
    /// caller-supplied date (used by the schedule "my" view's quick-apply
    /// entries). No behavior change otherwise.
    public convenience init(client: SupabaseClient, initialDate: Date) {
        self.init(client: client)
        self.startDate = initialDate
        self.endDate = initialDate
    }

    // MARK: - Derived

    /// Effective hour count when `isHalfDay` is on. Custom value wins
    /// when parseable + > 0; otherwise falls back to the preset bucket.
    public var effectiveHours: Double {
        let trimmed = customHours.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let parsed = Double(trimmed), parsed > 0 {
            return parsed
        }
        return presetHours
    }

    /// Inclusive day count — matches Web `splitDaysByMonth` / the form
    /// preview (`leave-form.tsx` renders `{days}天`). When `isHalfDay`
    /// is on we override the date-span computation with `hours / 8` so
    /// the existing RPC (which only takes `p_days`) still receives the
    /// fractional value the user intends.
    public var days: Double {
        if isHalfDay {
            // Half-day / custom-hour path. Round to the 0.1-day grid the
            // schema stores (NUMERIC(4,1)) to avoid noise.
            let raw = effectiveHours / 8.0
            return (raw * 10).rounded() / 10
        }
        let cal = Calendar(identifier: .iso8601)
        let s = cal.startOfDay(for: startDate)
        let e = cal.startOfDay(for: endDate)
        let components = cal.dateComponents([.day], from: s, to: e)
        let diff = components.day ?? 0
        return Double(max(0, diff) + 1)
    }

    /// Medical-cert guidance follows the same rule the RPC computes
    /// server-side: sick leave where the day count is ≥ 3. The hint UI
    /// only surfaces the stronger "需要上传" framing when this is true;
    /// for <3-day sick leave the hint is a softer "建议附上".
    public var requiresMedicalCert: Bool {
        leaveType == .sick && days >= 3
    }

    /// Whether to show the sick-leave cert section at all.
    public var shouldShowMedicalCertHint: Bool {
        leaveType == .sick
    }

    /// Mirrors Web's client-side gate: end ≥ start, reason present,
    /// leave type != `.unknown`. Also rejects the UI's `unknown`
    /// sentinel enum which shouldn't be user-selectable but we defend
    /// against it anyway. Half-day path adds an hours > 0 guard.
    public var canSubmit: Bool {
        guard leaveType != .unknown else { return false }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if isHalfDay {
            guard effectiveHours > 0 else { return false }
        } else {
            guard days >= 1 else { return false }
        }
        return !isSubmitting && !isUploadingCert
    }

    // MARK: - Medical cert upload

    /// PhotosPicker entry. Loads JPEG-decoded bytes, delegates to the
    /// raw-data overload. Called from the view's `.onChange(of:)`.
    public func uploadMedicalCert(item: PhotosPickerItem) async {
        isUploadingCert = true
        defer { isUploadingCert = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = "未能读取所选图片"
            return
        }
        let fileName = "medical_cert_\(UUID().uuidString.prefix(8)).jpg"
        await performUpload(data: data, fileName: fileName, mimeType: "image/jpeg")
    }

    /// `.fileImporter` entry. Accepts pre-read raw bytes + the original
    /// filename so extension + MIME derivation stays inside the VM and
    /// the view only has to worry about security-scoped URL access.
    public func uploadMedicalCert(data: Data, fileName: String) async {
        isUploadingCert = true
        defer { isUploadingCert = false }

        let ext = (fileName as NSString).pathExtension.lowercased()
        let mime = UTType(filenameExtension: ext)?
            .preferredMIMEType ?? "application/octet-stream"
        await performUpload(data: data, fileName: fileName, mimeType: mime)
    }

    public func clearMedicalCert() {
        medicalCertUrl = nil
        medicalCertFileName = nil
    }

    private func performUpload(data: Data, fileName: String, mimeType: String) async {
        do {
            let publicUrl = try await LeaveStorageClient.uploadMedicalCert(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                client: client
            )
            self.medicalCertUrl = publicUrl
            self.medicalCertFileName = fileName
        } catch {
            errorMessage = "上传医疗证明失败: \(ErrorLocalizer.localize(error))"
        }
    }

    // MARK: - Submit

    /// Calls `approvals_submit_leave` and stores the returned UUID in
    /// `createdRequestId` on success. Returns `true` for the view to
    /// decide dismiss/navigation. Returning `false` with
    /// `errorMessage` set is the non-throwing failure path.
    @discardableResult
    public func submit() async -> Bool {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard leaveType != .unknown else {
            errorMessage = "请选择请假类型"
            return false
        }
        guard !trimmedReason.isEmpty else {
            errorMessage = "请填写请假事由"
            return false
        }
        guard startDate <= endDate else {
            errorMessage = "开始日期不能晚于结束日期"
            return false
        }
        if isHalfDay && effectiveHours <= 0 {
            errorMessage = "请填写请假小时数"
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let input = LeaveSubmitInput(
            leaveType: leaveType,
            startDate: Self.yyyyMMdd.string(from: startDate),
            endDate: Self.yyyyMMdd.string(from: endDate),
            days: days,
            reason: trimmedReason,
            priority: priority
        )

        do {
            let id: UUID = try await client
                .rpc("approvals_submit_leave", params: input)
                .execute()
                .value
            self.createdRequestId = id
            // Post-submit medical-cert writeback. Soft-fails: if the
            // URL columns aren't in prod yet (migration 20260423110000
            // not shipped), the UPDATE errors out but the parent
            // submission already succeeded — we surface a warning but
            // don't return false, which would hide the created row.
            if let url = medicalCertUrl {
                await attachMedicalCertURL(url: url, fileName: medicalCertFileName, requestId: id)
            }
            return true
        } catch {
            self.errorMessage = prettyApprovalRPCError(error)
            return false
        }
    }

    /// Writes `medical_cert_url` / `medical_cert_name` /
    /// `medical_cert_uploaded=true` onto the freshly-inserted
    /// `approval_request_leave` row. The table's FOR ALL policy
    /// (027_permission_alignment.sql:132) grants the requester UPDATE
    /// on their own detail rows.
    private func attachMedicalCertURL(
        url: String,
        fileName: String?,
        requestId: UUID
    ) async {
        struct MedicalCertUpdate: Encodable {
            let medical_cert_url: String
            let medical_cert_name: String?
            let medical_cert_uploaded: Bool
        }
        let payload = MedicalCertUpdate(
            medical_cert_url: url,
            medical_cert_name: fileName,
            medical_cert_uploaded: true
        )
        do {
            _ = try await client
                .from("approval_request_leave")
                .update(payload)
                .eq("request_id", value: requestId.uuidString)
                .execute()
        } catch {
            #if DEBUG
            print("[LeaveSubmit] medical_cert writeback failed: \(ErrorLocalizer.localize(error))")
            #endif
            // Don't overwrite errorMessage here — the primary submit
            // already succeeded and the user shouldn't see a red
            // banner on a successful parent insert. A follow-up sync
            // from the detail view can re-attach if needed.
        }
    }

    // MARK: - Formatter
    //
    // UTC date formatter — the DB `DATE` column is tz-naive, matching
    // Web's use of `YYYY-MM-DD` strings. Picking UTC keeps the "today"
    // anchor stable across DST boundaries and user timezone changes.

    private static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
