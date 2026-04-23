import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Batch B.3 — Business trip submit ViewModel.
//
// Writes directly to `business_trip_requests` (migration 045). No
// RPC wrapper exists on the server because Web never shipped a user-
// facing business-trip submission form, even though the schema has
// existed since Phase 2 and the approval queue already reads from
// this table.
//
// Trust boundary: the RLS INSERT policy on business_trip_requests is
// `WITH CHECK (auth.uid() = user_id)` (migration 045:74). A user-JWT
// can't forge user_id or status — status defaults to 'pending' at the
// DB level, and approved_by / approved_at can only be written by a
// row holding an approver role (045:97-112). No `status='approved'`
// forgery is possible.
//
// Date validity: the DB enforces end_date >= start_date via
// `CONSTRAINT business_trip_dates_valid` (045:29). The VM pre-checks
// client-side for a snappier UX. There is no "must submit N days in
// advance" guard — business trips can be same-day.
//
// No auto-approve / approver-routing side-effect: since this path
// doesn't create an `approval_requests` companion row, the approval
// queue resolves business trips via `approval_request_id IS NULL` +
// direct table listings. If / when Web adds a submit RPC that ties
// the FK, the iOS VM should switch to that RPC for parity with the
// trust-boundary argument in 20260421180000_approvals_submit_rpcs.sql.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class BusinessTripSubmitViewModel: ObservableObject {
    // MARK: - Form state

    @Published public var startDate: Date = Date()
    @Published public var endDate: Date = Date()
    @Published public var destination: String = ""
    @Published public var purpose: String = ""
    @Published public var transportation: BusinessTripTransportation? = nil
    @Published public var estimatedCost: String = ""   // Yuan, free-form

    // MARK: - Submit state

    @Published public private(set) var isSubmitting: Bool = false
    @Published public var errorMessage: String?
    @Published public private(set) var createdRequestId: UUID?

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    /// Batch C.3 — quick-apply overload. Pre-fills both endpoints from a
    /// caller-supplied date (schedule "my" view's 快速申请 entries).
    public convenience init(client: SupabaseClient, initialDate: Date) {
        self.init(client: client)
        self.startDate = initialDate
        self.endDate = initialDate
    }

    // MARK: - Derived

    public var canSubmit: Bool {
        guard !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard startDate <= endDate else { return false }
        return !isSubmitting
    }

    // MARK: - Submit

    /// Inserts a new row into `business_trip_requests` via PostgREST
    /// and stores the generated UUID in `createdRequestId` on success.
    /// The insert body carries only user-writable columns — the rest
    /// (status, timestamps, approval_request_id) default server-side
    /// or stay NULL.
    @discardableResult
    public func submit() async -> Bool {
        let trimmedDest = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDest.isEmpty else {
            errorMessage = "请填写出差地点"
            return false
        }
        guard !trimmedPurpose.isEmpty else {
            errorMessage = "请填写出差事由"
            return false
        }
        guard startDate <= endDate else {
            errorMessage = "结束日期不能早于开始日期"
            return false
        }

        // Parse estimated cost. Empty is fine (optional column);
        // a non-empty but unparseable string should error early so
        // the user doesn't silently submit without the cost they
        // expected to attach.
        let costTrimmed = estimatedCost.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedCost: Double? = nil
        if !costTrimmed.isEmpty {
            guard let v = Double(costTrimmed), v >= 0 else {
                errorMessage = "预计费用应为非负数值"
                return false
            }
            parsedCost = v
        }

        // Resolve the current user's UUID. Without a session we can't
        // satisfy the RLS WITH CHECK. Surface an explicit error rather
        // than letting the insert fail with an opaque PostgREST response.
        let userId: UUID
        do {
            userId = try await client.auth.session.user.id
        } catch {
            errorMessage = "请先登录"
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let payload = BusinessTripSubmitInput(
            userId: userId,
            startDate: Self.yyyyMMdd.string(from: startDate),
            endDate: Self.yyyyMMdd.string(from: endDate),
            destination: trimmedDest,
            purpose: trimmedPurpose,
            transportation: transportation,
            estimatedCost: parsedCost
        )

        struct InsertedRow: Decodable { let id: UUID }

        do {
            let row: InsertedRow = try await client
                .from("business_trip_requests")
                .insert(payload)
                .select("id")
                .single()
                .execute()
                .value
            self.createdRequestId = row.id
            return true
        } catch {
            self.errorMessage = prettyApprovalRPCError(error)
            return false
        }
    }

    private static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
