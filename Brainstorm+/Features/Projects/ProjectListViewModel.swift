import Foundation
import Combine
import Supabase

@MainActor
public class ProjectListViewModel: ObservableObject {
    @Published public var projects: [Project] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    /// Free-text search applied to `projects.name`.
    ///
    /// 1.5: pushed to server-side `ilike('name', '%q%')` on the next `fetchProjects(...)` call.
    /// Web parity: `src/lib/actions/projects.ts` — `query = query.ilike('name', `%${filters.search}%`)`.
    @Published public var searchText: String = ""

    /// Optional status filter. `nil` means "all statuses".
    ///
    /// 1.5: pushed to server-side `eq('status', s)` on the next `fetchProjects(...)` call.
    /// Web parity: `src/lib/actions/projects.ts` — `query = query.eq('status', filters.status)`.
    @Published public var statusFilter: Project.ProjectStatus? = nil

    /// Records how membership scoping was applied on the most recent `fetchProjects(...)`.
    ///
    /// Lets the view distinguish:
    /// - admin: no scoping applied — saw all rows the server returned
    /// - member: scoped through `project_members`, returned rows for this user
    /// - noMembership: non-admin user had zero `project_members` rows — returning empty is correct
    /// - unknown: never fetched yet
    public enum ScopeOutcome: Equatable {
        case unknown
        case admin
        case member
        case noMembership
    }
    @Published public var scopeOutcome: ScopeOutcome = .unknown

    /// 1.7: owner `profiles` summaries keyed by owner UUID, batched from a single
    /// `.from('profiles').in('id', ownerIds)` query after the main `projects` fetch.
    ///
    /// Mirrors Web list parity:
    /// ```ts
    /// .select('*, profiles:owner_id(full_name, avatar_url)')
    /// ```
    /// iOS uses a separate batch query (not a nested join) to keep the core `Project` model
    /// stable and to avoid fighting the Swift SDK's flat decode assumptions.
    ///
    /// This is best-effort: if the owner fetch fails, the list still renders with raw UUIDs
    /// (see `ProjectCardView` fallback).
    @Published public var ownersById: [UUID: ProjectOwnerSummary] = [:]

    /// Separate error surface for the owner-batch fetch so a profile-side failure does not
    /// clobber the primary `errorMessage` (which is reserved for the main projects query).
    @Published public var ownersErrorMessage: String? = nil

    /// 2.0: true while a row-level delete is in flight. Used by the row context menu and
    /// confirmation dialog to disable inputs and show a progress indicator. Distinct from
    /// `isLoading` (which is for the list fetch).
    @Published public var isDeleting: Bool = false

    /// 2.0: isolated error surface for delete failures so a destructive-action failure does
    /// not clobber `errorMessage` (list fetch) or `ownersErrorMessage` (owner hydrate).
    @Published public var deleteErrorMessage: String? = nil

    /// 2.1: best-effort task count per project, keyed by `project.id`, hydrated by a single
    /// batched `.from("tasks").select("project_id").in("project_id", ids)` follow-up query.
    ///
    /// **Web parity note**: Web's `Project` TypeScript interface declares `task_count?: number`
    /// but `fetchProjects()` does NOT select it, and the Projects list page does NOT display
    /// it. The 2.1 round records this as a source-of-truth discrepancy and ships the minimum
    /// auditable foundation iOS-side (batched client-side aggregation over `tasks`) so the
    /// list can meaningfully show a count without requiring a Web-side change first.
    ///
    /// `nil` value in the map means "not yet fetched" / "fetch failed"; UI falls back to
    /// hiding the count line rather than displaying `0` from a failed query.
    @Published public var taskCountsByProject: [UUID: Int] = [:]

    /// 2.1: separate error surface so a `tasks` count failure does not clobber the primary
    /// `errorMessage` (list fetch), `ownersErrorMessage` (owner hydrate), or
    /// `deleteErrorMessage` (destructive action). A counting failure is decorative — the list
    /// still renders its rows.
    @Published public var taskCountsErrorMessage: String? = nil

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    /// Fetch projects with Web-aligned semantics.
    ///
    /// Mirrors `fetchProjects()` in `BrainStorm+-Web/src/lib/actions/projects.ts`:
    /// - admin+ sees all projects (no membership scope)
    /// - non-admin is scoped to `project_members` rows for the current user
    /// - non-admin with zero memberships returns empty; does NOT fall back to reading all projects
    /// - search pushes to server-side `ilike('name', '%q%')`
    /// - status pushes to server-side `eq('status', s)`
    ///
    /// Role admin predicate mirrors `isAdmin()` in `BrainStorm+-Web/src/lib/rbac.ts`:
    /// `['admin', 'superadmin', 'chairperson', 'super_admin']`.
    /// On iOS, `PrimaryRole` is already normalized by `RBACManager.migrateLegacyRole()`,
    /// which folds `super_admin` into `.superadmin`, so we compare against the three canonical values.
    public func fetchProjects(role: PrimaryRole?, userId: UUID?) async {
        isLoading = true
        errorMessage = nil

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAdminCaller = Self.isAdmin(role: role)

        do {
            if isAdminCaller {
                self.projects = try await runProjectsQuery(
                    trimmedSearch: trimmedSearch,
                    scopedIds: nil
                )
                self.scopeOutcome = .admin
            } else {
                // Non-admin MUST go through membership scoping. If we don't have a user id
                // (e.g. profile hasn't loaded yet), return empty rather than leak all projects.
                guard let userId else {
                    self.projects = []
                    self.ownersById = [:]
                    self.ownersErrorMessage = nil
                    self.taskCountsByProject = [:]
                    self.taskCountsErrorMessage = nil
                    self.scopeOutcome = .noMembership
                    isLoading = false
                    return
                }

                let memberProjectIds = try await fetchMemberProjectIds(userId: userId)
                if memberProjectIds.isEmpty {
                    self.projects = []
                    self.ownersById = [:]
                    self.ownersErrorMessage = nil
                    self.taskCountsByProject = [:]
                    self.taskCountsErrorMessage = nil
                    self.scopeOutcome = .noMembership
                } else {
                    self.projects = try await runProjectsQuery(
                        trimmedSearch: trimmedSearch,
                        scopedIds: memberProjectIds
                    )
                    self.scopeOutcome = .member
                }
            }
            // 1.7: after the primary list fetch, best-effort hydrate `ownersById` so cards can
            // show the owner's human-readable name. A failure here does NOT roll back the list.
            await refreshOwnersForCurrentProjects()
            // 2.1: single batched follow-up query against `tasks` to populate the per-project
            // task count map. Gated on non-empty `projects` inside the helper; failure is
            // soft (see `taskCountsErrorMessage`) and never touches the main list fetch.
            await refreshTaskCountsForCurrentProjects()
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Admin predicate

    private static func isAdmin(role: PrimaryRole?) -> Bool {
        switch role {
        case .admin, .superadmin, .chairperson: return true
        case .employee, .none: return false
        }
    }

    // MARK: - Server-side query composition

    /// Builds the `projects` select with server-side filters applied.
    /// - `scopedIds` nil → no `.in('id', ...)` clause (admin path)
    /// - `scopedIds` non-nil → `.in('id', ...)` (non-admin membership scope)
    private func runProjectsQuery(trimmedSearch: String, scopedIds: [UUID]?) async throws -> [Project] {
        var query = client
            .from("projects")
            .select()

        if let scopedIds {
            query = query.in("id", values: scopedIds)
        }
        if let statusFilter {
            query = query.eq("status", value: statusFilter.rawValue)
        }
        if !trimmedSearch.isEmpty {
            query = query.ilike("name", pattern: "%\(trimmedSearch)%")
        }

        // 1.6: aligned with Web `fetchProjects()` which orders by `created_at DESC`
        // (see `BrainStorm+-Web/src/lib/actions/projects.ts`). Previously `updated_at DESC`.
        return try await query
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    private struct MembershipRow: Decodable {
        let projectId: UUID
        enum CodingKeys: String, CodingKey { case projectId = "project_id" }
    }

    private func fetchMemberProjectIds(userId: UUID) async throws -> [UUID] {
        let rows: [MembershipRow] = try await client
            .from("project_members")
            .select("project_id")
            .eq("user_id", value: userId)
            .execute()
            .value
        return rows.map(\.projectId)
    }

    // MARK: - 1.7 owner batch hydrate

    /// Best-effort: look up each distinct non-nil `project.ownerId` against `profiles` in one
    /// batched `.in('id', ownerIds)` query. Populates `ownersById` so `ProjectCardView` can
    /// render `full_name` instead of a raw UUID.
    ///
    /// Failure mode: on any error we clear `ownersById` and record a message on
    /// `ownersErrorMessage`, but leave `projects` / `errorMessage` / `scopeOutcome` untouched
    /// so the list still shows rows (with UUID fallback in the card).
    private func refreshOwnersForCurrentProjects() async {
        let ownerIds = Array(Set(projects.compactMap { $0.ownerId }))
        guard !ownerIds.isEmpty else {
            self.ownersById = [:]
            self.ownersErrorMessage = nil
            return
        }
        do {
            let rows: [ProjectOwnerSummary] = try await client
                .from("profiles")
                .select("id, full_name, avatar_url")
                .in("id", values: ownerIds)
                .execute()
                .value
            var map: [UUID: ProjectOwnerSummary] = [:]
            for row in rows { map[row.id] = row }
            self.ownersById = map
            self.ownersErrorMessage = nil
        } catch {
            // Keep the project rows visible with UUID-fallback cards; surface a soft error.
            self.ownersById = [:]
            self.ownersErrorMessage = error.localizedDescription
        }
    }

    // MARK: - 2.1 Task count hydrate

    /// Per-task-row projection used to aggregate counts client-side. Only `project_id` is
    /// selected, so the over-the-wire payload is minimal even when a project has many tasks.
    private struct TaskProjectIdRow: Decodable {
        let projectId: UUID
        enum CodingKeys: String, CodingKey { case projectId = "project_id" }
    }

    /// Issues ONE batched `.from("tasks").select("project_id").in("project_id", ids)` query
    /// and groups the returned `project_id` values into `taskCountsByProject`.
    ///
    /// Explicitly NOT N+1 — a single PostgREST round-trip hydrates counts for every project
    /// in the current list, independent of how many projects or tasks there are.
    ///
    /// Source-of-truth note: Web's `Project` TypeScript interface declares `task_count?` but
    /// `fetchProjects()` never selects it and the list page never displays it. 2.1 records
    /// this as a Web source-of-truth discrepancy and delivers the minimum auditable
    /// foundation on iOS (batched aggregate, not per-project N+1).
    ///
    /// Failure mode: records `taskCountsErrorMessage` and clears `taskCountsByProject`. Does
    /// NOT clear `projects`, does NOT set `errorMessage`, does NOT touch `ownersById`. Cards
    /// fall through to hiding the count line rather than showing a stale or zeroed value.
    private func refreshTaskCountsForCurrentProjects() async {
        let projectIds = projects.map(\.id)
        guard !projectIds.isEmpty else {
            self.taskCountsByProject = [:]
            self.taskCountsErrorMessage = nil
            return
        }
        do {
            let rows: [TaskProjectIdRow] = try await client
                .from("tasks")
                .select("project_id")
                .in("project_id", values: projectIds)
                .execute()
                .value

            // Initialize every project in the current list at 0 so cards can render "0 tasks"
            // for projects that have none, rather than rendering nothing at all.
            var counts: [UUID: Int] = [:]
            for id in projectIds { counts[id] = 0 }
            for row in rows {
                counts[row.projectId, default: 0] += 1
            }
            self.taskCountsByProject = counts
            self.taskCountsErrorMessage = nil
        } catch {
            // Keep project rows visible; cards will hide the count line via the nil fallback.
            self.taskCountsByProject = [:]
            self.taskCountsErrorMessage = error.localizedDescription
        }
    }

    // MARK: - 2.0 Delete

    /// Mirrors Web `deleteProject(id)` in `BrainStorm+-Web/src/lib/actions/projects.ts`:
    ///
    /// ```ts
    /// const { error } = await supabase.from('projects').delete().eq('id', id)
    /// ```
    ///
    /// Only the `projects` row is targeted. `project_members` cascade-deletes via a Postgres FK
    /// (`ON DELETE CASCADE`), so iOS deliberately does NOT re-implement cascade logic client-side.
    ///
    /// On success the row is stripped from `projects` locally so the list reflects the server
    /// truth without an extra round-trip. On failure `deleteErrorMessage` is set and `projects`
    /// is left untouched (no optimistic removal — the row wasn't actually deleted on the server).
    public func deleteProject(id: UUID) async -> Bool {
        isDeleting = true
        deleteErrorMessage = nil
        do {
            _ = try await client
                .from("projects")
                .delete()
                .eq("id", value: id)
                .execute()
            self.projects.removeAll { $0.id == id }
            isDeleting = false
            return true
        } catch {
            deleteErrorMessage = error.localizedDescription
            isDeleting = false
            return false
        }
    }

    /// Used by the detail view's `onProjectDeleted` callback: the detail view has already
    /// confirmed the server-side delete, so the list just needs to drop the row locally.
    /// Kept separate from `deleteProject(id:)` so we don't issue a redundant PostgREST call.
    public func removeProjectLocally(id: UUID) {
        self.projects.removeAll { $0.id == id }
    }

    // MARK: - Display helper

    /// Thin, defensive display-layer filter.
    ///
    /// With 1.5 the primary filter is server-side, so in the common case this is a pass-through.
    /// Kept for two reasons:
    /// 1. Resilience — if the server returned a superset (e.g. stale fetch race), the UI still
    ///    reflects the active filter immediately.
    /// 2. Instant feedback — while a re-fetch is in flight, the existing rows are still filtered
    ///    by the latest typed search text.
    ///
    /// This is NOT a claim of Web parity; it is strictly a UI smoothing layer on top of the
    /// server-authoritative result.
    public var filteredProjects: [Project] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && statusFilter == nil { return projects }
        return projects.filter { project in
            if let statusFilter, project.status != statusFilter { return false }
            if !trimmed.isEmpty {
                return project.name.range(of: trimmed, options: .caseInsensitive) != nil
            }
            return true
        }
    }
}
