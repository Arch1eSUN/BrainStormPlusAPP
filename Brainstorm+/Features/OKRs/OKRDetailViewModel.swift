import Foundation
import Combine
import Supabase

/// Drives `OKRDetailView` for a single objective + its key results.
///
/// Web doesn't ship a separate `/dashboard/okr/[id]` route — the OKR page
/// is a single list with inline expand-collapse. We provide a pushed
/// detail on iOS because SwiftUI navigation reads better than a mobile
/// accordion for long-form description + owner info.
///
/// Read-only; no KR progress slider / status transition buttons / delete
/// affordance this pass. Matches the Phase 2.3 scope note.
@MainActor
public class OKRDetailViewModel: ObservableObject {
    @Published public private(set) var objective: Objective
    @Published public private(set) var owner: Profile? = nil
    @Published public private(set) var assignee: Profile? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let client: SupabaseClient

    /// Exposed so the view can spin up an `OKRListViewModel` ad-hoc for
    /// mutations (status transitions, delete, KR meta edits) without
    /// threading a second VM through every navigation call site.
    public var supabaseClient: SupabaseClient { client }

    public init(client: SupabaseClient, initial: Objective) {
        self.client = client
        self.objective = initial
    }

    /// Refresh the objective + its KRs + its owner/assignee profiles.
    /// Web shows owner/assignee through `fetchProfileMap` in
    /// `okr.ts:69-82` — we replicate that with a batched `.in("id", ...)`.
    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let refreshed: Objective = try await client
                .from("objectives")
                .select("*, key_results(*)")
                .eq("id", value: objective.id)
                .single()
                .execute()
                .value
            self.objective = refreshed

            // Hydrate owner + assignee profiles (may be the same user).
            var ids = Set<UUID>()
            if let o = refreshed.ownerId { ids.insert(o) }
            if let a = refreshed.assigneeId { ids.insert(a) }

            guard !ids.isEmpty else { return }
            let profiles: [Profile] = try await client
                .from("profiles")
                .select("id, full_name, display_name, avatar_url, position, department, role, status")
                .in("id", values: ids.map { $0.uuidString })
                .execute()
                .value

            let byId = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            self.owner = refreshed.ownerId.flatMap { byId[$0] }
            self.assignee = refreshed.assigneeId.flatMap { byId[$0] }
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }
}
