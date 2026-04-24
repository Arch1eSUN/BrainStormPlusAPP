import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Payroll List ViewModel
// ──────────────────────────────────────────────────────────────────
// Bug fix: previous implementation queried `payroll_records` without
// any user filter and relied entirely on RLS to scope rows. For
// privileged roles (admin / superadmin / finance_ops) that meant they
// saw whatever RLS returned (often nothing / own rows only depending
// on policy), and for unprivileged users it leaked on any RLS gap.
//
// We now:
//   • Default to `.mine` scope → explicit `.eq("user_id", uid)`.
//   • Expose `.all` scope for finance_ops / admin-tier, querying
//     without the user_id filter (RLS is still the authoritative
//     enforcement layer — if RLS is misconfigured, add the policy
//     backend-side; do NOT trust the client filter).
//   • Expose `canEdit` so the View can render create/edit affordances
//     only for privileged users.
// ══════════════════════════════════════════════════════════════════

public enum PayrollScope: String, CaseIterable, Hashable {
    case mine
    case all
}

@MainActor
public class PayrollListViewModel: ObservableObject {
    @Published public var payrolls: [PayrollRecord] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var scope: PayrollScope = .mine

    @Published public private(set) var viewerPrimaryRole: PrimaryRole = .employee
    @Published public private(set) var viewerCapabilities: [Capability] = []

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // ── RBAC gates (mirror Web payroll page gate) ──
    /// True if viewer is finance_ops-capable OR admin-tier; these
    /// users can toggle scope + see everyone's payroll.
    public var canViewAll: Bool {
        if viewerPrimaryRole == .admin || viewerPrimaryRole == .superadmin { return true }
        return RBACManager.shared.hasCapability(.finance_ops, in: viewerCapabilities)
    }

    /// True if viewer can create / edit payroll rows for any user.
    /// Same gate as `canViewAll` — finance_ops or admin-tier.
    public var canEdit: Bool { canViewAll }

    /// Binds session profile so the VM can resolve caps/role before
    /// fetching. Call from the View `.task` / `.onAppear`.
    public func bind(sessionProfile: Profile?) {
        guard let profile = sessionProfile else {
            viewerPrimaryRole = .employee
            viewerCapabilities = []
            // Non-privileged → force scope back to mine.
            if scope != .mine { scope = .mine }
            return
        }
        viewerPrimaryRole = RBACManager.shared.migrateLegacyRole(profile.role).primaryRole
        viewerCapabilities = RBACManager.shared.getEffectiveCapabilities(for: profile)
        // If a previously-privileged user lost the cap mid-session,
        // snap scope back to `.mine` to avoid stale `.all` state.
        if !canViewAll && scope != .mine { scope = .mine }
    }

    public func setScope(_ newScope: PayrollScope) async {
        // Guard: unprivileged viewers can never switch to `.all`.
        let target: PayrollScope = (newScope == .all && !canViewAll) ? .mine : newScope
        if target == scope { return }
        scope = target
        await fetchPayrolls()
    }

    public func fetchPayrolls() async {
        isLoading = true
        errorMessage = nil
        do {
            // Resolve effective scope: defensively collapse `.all` →
            // `.mine` for non-privileged viewers even if someone set
            // it externally. RLS is still the authoritative gate.
            let effectiveScope: PayrollScope = (scope == .all && canViewAll) ? .all : .mine

            switch effectiveScope {
            case .all:
                // Privileged: no client-side user_id filter. RLS must
                // allow finance_ops / admin to read other users' rows.
                self.payrolls = try await client
                    .from("payroll_records")
                    .select()
                    .order("period", ascending: false)
                    .execute()
                    .value

            case .mine:
                // Existing behavior: own records only. Explicit filter
                // defends against RLS drift where a policy accidentally
                // widens read scope.
                let userId = try await client.auth.session.user.id
                self.payrolls = try await client
                    .from("payroll_records")
                    .select()
                    .eq("user_id", value: userId)
                    .order("period", ascending: false)
                    .execute()
                    .value
            }
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
        isLoading = false
    }
}
