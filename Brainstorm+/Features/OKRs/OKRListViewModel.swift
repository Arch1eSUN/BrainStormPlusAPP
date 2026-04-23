import Foundation
import Combine
import Supabase

/// View model backing `OKRListView`. Mirrors Web's `OkrPage` in
/// `BrainStorm+-Web/src/app/dashboard/okr/page.tsx` +
/// `fetchObjectives` / `fetchOkrStats` in
/// `BrainStorm+-Web/src/lib/actions/okr.ts:86-148`.
///
/// ── Visibility model ───────────────────────────────────────────────────
/// Web RLS on `public.objectives` is `FOR SELECT USING (true)` (see
/// `BrainStorm+-Web/supabase/migrations/004_schema_alignment.sql:149-158`)
/// and the matching row on `key_results` (`:160-163`). That means **every
/// authenticated user sees every OKR in the workspace** — there is no
/// self/manager/department gating. Only writes are restricted:
/// owner OR admin/manager via the `Owners manage objectives` policy.
///
/// iOS mirrors this faithfully: the list is fetched with no client-side
/// filter on `owner_id` / `assignee_id`. Web's server action *does* compute
/// `org_id` on insert, so the server already limits what the session can
/// read — we don't add any extra scope.
///
/// Read-only surface for this pass: no create/edit/delete/check-in. Those
/// land in a later iOS batch.
@MainActor
public class OKRListViewModel: ObservableObject {
    @Published public private(set) var objectives: [Objective] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    /// Selected period, in Web's `yyyy-Q{1-4}` format (e.g. `2026-Q1`).
    /// Defaults to the current calendar quarter at construction time —
    /// mirrors Web defaulting to `2026-Q1` in `page.tsx:32`.
    @Published public var period: String

    private let client: SupabaseClient

    public init(client: SupabaseClient, initialPeriod: String? = nil) {
        self.client = client
        self.period = initialPeriod ?? Self.currentQuarter()
    }

    // MARK: - Period helpers

    /// Returns the current calendar-year quarter as `yyyy-Q{1-4}`.
    public static func currentQuarter(reference: Date = Date()) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: reference)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        let q = ((month - 1) / 3) + 1
        return "\(year)-Q\(q)"
    }

    /// Parses a period string back into `(year, quarter)` for the picker.
    public static func parsePeriod(_ period: String) -> (year: Int, quarter: Int)? {
        // Format: "yyyy-Q{1-4}"
        let parts = period.split(separator: "-")
        guard parts.count == 2 else { return nil }
        guard let year = Int(parts[0]) else { return nil }
        let qStr = parts[1]
        guard qStr.hasPrefix("Q"), let q = Int(qStr.dropFirst()) else { return nil }
        return (year, q)
    }

    public static func formatPeriod(year: Int, quarter: Int) -> String {
        "\(year)-Q\(quarter)"
    }

    /// Year range offered by the picker — Web hardcodes 2026 only, iOS
    /// allows one year back / forward for flexibility.
    public var availableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return [current - 1, current, current + 1]
    }

    public var availableQuarters: [Int] { [1, 2, 3, 4] }

    // MARK: - Derived stats (mirror Web `fetchOkrStats`)

    public struct Stats: Equatable {
        public let totalObjectives: Int
        public let avgProgress: Int
        public let completedCount: Int
        /// Objectives with `status == .active` AND `computedProgress < 30`.
        /// Matches Web `okr.ts:139`.
        public let atRiskCount: Int
    }

    public var stats: Stats {
        let total = objectives.count
        if total == 0 {
            return Stats(totalObjectives: 0, avgProgress: 0, completedCount: 0, atRiskCount: 0)
        }
        let avg = objectives.reduce(0) { $0 + $1.computedProgress } / total
        let completed = objectives.filter { $0.status == .completed }.count
        let atRisk = objectives.filter {
            $0.status == .active && $0.computedProgress < 30
        }.count
        return Stats(
            totalObjectives: total,
            avgProgress: avg,
            completedCount: completed,
            atRiskCount: atRisk
        )
    }

    /// Mirrors the header badge in `page.tsx:276` — mean of mean-of-KRs
    /// across all visible objectives (unweighted).
    public var overallProgress: Int {
        guard !objectives.isEmpty else { return 0 }
        let sum = objectives.reduce(0) { $0 + $1.computedProgress }
        return sum / objectives.count
    }

    // MARK: - Fetch

    /// Mirrors Web `fetchObjectives(period)` in `okr.ts:86-110` — embeds KRs
    /// via PostgREST's nested select syntax (`objectives(*, key_results(*))`).
    public func fetchObjectives() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows: [Objective] = try await client
                .from("objectives")
                .select("*, key_results(*)")
                .eq("period", value: period)
                .order("created_at", ascending: false)
                .execute()
                .value
            self.objectives = rows
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }
}
