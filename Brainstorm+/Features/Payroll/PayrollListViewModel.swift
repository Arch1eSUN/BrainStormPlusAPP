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

    /// Active employee directory for the admin create/edit picker. Loaded
    /// on-demand via `loadEmployeeDirectory()` — NOT fetched eagerly.
    @Published public private(set) var employeeDirectory: [EmployeeDirectoryEntry] = []
    @Published public private(set) var isLoadingDirectory: Bool = false

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // ══════════════════════════════════════════════════════════════════
    // Admin input / directory types
    // ══════════════════════════════════════════════════════════════════

    /// Minimal payload surface for `adminSavePayroll`. Mirrors the Web
    /// whitelist in `payroll.ts` line 142-182 — mobile edition restricts
    /// to the core 4 money fields; advanced fields (paid_leave_days etc.)
    /// remain Web-only until a dedicated admin compute flow lands on iOS.
    public struct AdminPayrollInput: Hashable {
        public let userId: UUID
        public let period: String
        public let baseSalary: Decimal
        public let bonus: Decimal
        public let deductions: Decimal

        public init(
            userId: UUID,
            period: String,
            baseSalary: Decimal,
            bonus: Decimal,
            deductions: Decimal
        ) {
            self.userId = userId
            self.period = period
            self.baseSalary = baseSalary
            self.bonus = bonus
            self.deductions = deductions
        }

        /// net_pay is computed client-side to match Web:
        /// `(base_salary ?? 0) + (bonus ?? 0) - (deductions ?? 0)`
        /// (payroll.ts line 156). The server has no trigger doing this,
        /// so we must send the pre-computed value in the payload.
        public var netPay: Decimal {
            baseSalary + bonus - deductions
        }
    }

    /// Row shape for the admin employee picker. Sourced from `profiles`.
    public struct EmployeeDirectoryEntry: Identifiable, Hashable, Decodable {
        public let id: UUID
        public let fullName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case fullName = "full_name"
        }
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

    // ══════════════════════════════════════════════════════════════════
    // Admin CRUD (finance_ops / admin-tier only)
    // ══════════════════════════════════════════════════════════════════

    /// Load the active employee directory for the admin picker.
    ///
    /// Mirrors Web `profiles.select('id, full_name').eq('status', 'active')`
    /// ordered by `full_name`. RLS still gates this — if the viewer lacks
    /// read access on `profiles`, this will return an empty list and
    /// surface the error via `errorMessage`.
    public func loadEmployeeDirectory() async {
        guard canEdit else {
            errorMessage = "无权限"
            return
        }
        isLoadingDirectory = true
        defer { isLoadingDirectory = false }
        do {
            let rows: [EmployeeDirectoryEntry] = try await client
                .from("profiles")
                .select("id, full_name")
                .eq("status", value: "active")
                .order("full_name", ascending: true)
                .execute()
                .value
            self.employeeDirectory = rows
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    /// Mirrors Web payroll.ts adminSavePayroll line 142-182.
    ///
    /// Upserts a single payroll_records row on the `(user_id, period)`
    /// unique key. The mobile edition restricts the payload to the core
    /// money fields (base / bonus / deductions / net_pay) — richer fields
    /// (leave days, fines, calculation_version) stay Web-only.
    @discardableResult
    public func adminSavePayroll(record: AdminPayrollInput) async -> Bool {
        guard canEdit else {
            errorMessage = "无权限"
            return false
        }

        let payload = AdminPayrollUpsertPayload(
            userId: record.userId,
            period: record.period,
            baseSalary: record.baseSalary,
            bonus: record.bonus,
            deductions: record.deductions,
            netPay: record.netPay
        )

        do {
            try await client
                .from("payroll_records")
                .upsert(payload, onConflict: "user_id, period")
                .execute()

            // Activity log — non-blocking (never breaks main flow).
            let userName = employeeDirectory.first(where: { $0.id == record.userId })?.fullName
                ?? record.userId.uuidString
            await ActivityLogWriter.write(
                client: client,
                type: .system,
                action: "payroll_update",
                description: "更新了 \(userName) 在 \(record.period) 的薪酬",
                entityType: "payroll_record",
                entityId: nil,
                targetId: record.userId
            )

            // Refresh the list so the new / updated row is visible.
            await fetchPayrolls()
            return true
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
            return false
        }
    }

    /// Delete a single payroll_records row. Web has no direct 1-to-1
    /// equivalent (Web clears periods in bulk via `clearPayrollPeriod`) —
    /// the mobile edition exposes a per-row delete for quick corrections.
    /// RLS is still the authoritative gate on who can delete what.
    @discardableResult
    public func adminDeletePayroll(id: UUID, userId: UUID, period: String) async -> Bool {
        guard canEdit else {
            errorMessage = "无权限"
            return false
        }
        do {
            try await client
                .from("payroll_records")
                .delete()
                .eq("id", value: id)
                .execute()

            // Optimistic local strip so the UI doesn't briefly show the
            // deleted row while `fetchPayrolls` round-trips.
            self.payrolls.removeAll { $0.id == id }

            let userName = employeeDirectory.first(where: { $0.id == userId })?.fullName
                ?? userId.uuidString
            await ActivityLogWriter.write(
                client: client,
                type: .system,
                action: "payroll_delete",
                description: "删除了 \(userName) 在 \(period) 的薪酬记录",
                entityType: "payroll_record",
                entityId: id,
                targetId: userId
            )

            await fetchPayrolls()
            return true
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
            return false
        }
    }

    // MARK: - Private payloads

    private struct AdminPayrollUpsertPayload: Encodable {
        let userId: UUID
        let period: String
        let baseSalary: Decimal
        let bonus: Decimal
        let deductions: Decimal
        let netPay: Decimal

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case period
            case baseSalary = "base_salary"
            case bonus
            case deductions
            case netPay = "net_pay"
        }
    }
}
