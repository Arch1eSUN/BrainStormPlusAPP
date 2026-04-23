import Foundation
import Combine
import Supabase

/// Sprint 4.1 — read-only foundation for the Approvals module.
///
/// Single-purpose ViewModel that loads the current user's own approval
/// submissions, mirroring Web `listMySubmissions` in
/// `src/lib/actions/approval-requests.ts:555-621`. Deliberately *not*
/// named `ApprovalsViewModel` — sprint 4.3's approver-queue screen will
/// get its own `ApprovalQueueViewModel`; keeping viewmodels single-
/// purpose avoids a god-object and matches how Chat split
/// `ChatListViewModel` vs `ChatRoomViewModel`.
@MainActor
public final class MySubmissionsViewModel: ObservableObject {
    // `rows` / `isLoading` are read-only from outside; `errorMessage` is
    // mutable so `.zyErrorBanner($vm.errorMessage)` can clear it on dismiss.
    @Published public private(set) var rows: [ApprovalMySubmissionRow] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    /// Replicates Web `listMySubmissions` (approval-requests.ts:555-621).
    ///
    /// Web uses `createAdminClient()` because the server action runs
    /// outside a request-bound client; the RLS SELECT on
    /// `approval_requests` is `USING (auth.uid() = requester_id)` which
    /// the user-JWT already satisfies — so no admin bypass is needed on
    /// iOS. Same posture as Projects' own-row fetches.
    ///
    /// The nested select returns `approval_request_leave` rows either as
    /// a single object, a 1-element array, or `null` depending on
    /// PostgREST's FK-uniqueness inference. `ApprovalMySubmissionRow`'s
    /// custom decoder handles all three shapes — see that file for the
    /// decoder logic.
    public func listMySubmissions(limit: Int = 100) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let currentUserId: UUID
        do {
            currentUserId = try await client.auth.session.user.id
        } catch {
            errorMessage = "请先登录"
            return
        }

        do {
            let fetched: [ApprovalMySubmissionRow] = try await client
                .from("approval_requests")
                .select("""
                    id,
                    request_type,
                    status,
                    priority_by_requester,
                    business_reason,
                    reviewer_note,
                    reviewed_at,
                    created_at,
                    approval_request_leave ( leave_type, start_date, end_date, days )
                """)
                .eq("requester_id", value: currentUserId.uuidString)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            self.rows = fetched
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }
}
