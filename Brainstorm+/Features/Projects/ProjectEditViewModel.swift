import Foundation
import Combine
import Supabase

// MARK: - 1.9 Project edit + member management foundation
//
// Mirrors Web `updateProject(id, updates)` + `fetchAllUsersForPicker()` +
// `fetchProjectMembers(projectId)` in `BrainStorm+-Web/src/lib/actions/projects.ts`.
//
// Scope (Round 1.9 foundation):
// - project row: `name`, `description`, `start_date`, `end_date`, `status`, `progress`, `updated_at`
// - membership: full rewrite of `project_members` rows for this project, always keeping `owner_id`
//
// Explicitly out of scope for 1.9: delete, AI summary, risk analysis, linked risk actions,
// resolution feedback, task_count. Those were documented as deferred after 1.7 / 1.8.

@MainActor
public class ProjectEditViewModel: ObservableObject {
    // MARK: - Inputs

    public let projectId: UUID
    /// Owner captured at init time so the picker can render the owner row as locked and the
    /// save step can protect the owner from accidental removal — mirrors Web:
    ///
    /// ```ts
    /// const ownerId = project?.owner_id
    /// if (ownerId) {
    ///   await supabase.from('project_members').delete().eq('project_id', id).neq('user_id', ownerId)
    /// }
    /// ```
    public let ownerId: UUID?
    /// Original member ids loaded at open time — used to detect whether to issue the member
    /// rewrite at save time. Matches Web's `if (member_ids !== undefined)` check: we only
    /// touch `project_members` if the user actually moved the selection.
    private(set) var originalMemberIds: Set<UUID> = []

    // MARK: - Form state

    @Published public var name: String
    @Published public var descriptionText: String
    @Published public var status: Project.ProjectStatus
    @Published public var progress: Int

    /// Start/end dates use an explicit include-toggle pair to match Web's `editForm.start_date || undefined`
    /// semantics — the user can leave a date "not included" and we simply do NOT send that column in the
    /// PostgREST payload (column value stays untouched on the server). If the toggle is ON we serialise
    /// the chosen `Date` as a `YYYY-MM-DD` string before POSTing so the server's `date` column ingests
    /// it safely (the Supabase Swift SDK default encoder would emit ISO8601 with time, which a `date`
    /// column would then have to coerce).
    @Published public var includeStartDate: Bool
    @Published public var startDate: Date
    @Published public var includeEndDate: Bool
    @Published public var endDate: Date

    // MARK: - Member picker state

    /// Result of `profiles.select('id, full_name, avatar_url, role, department').eq('status', 'active').order('full_name')`.
    /// Batched ONCE on open — explicitly NOT N+1 per user.
    @Published public var candidates: [ProjectMemberCandidate] = []
    /// Error surface for the candidates fetch. Isolated from `errorMessage` so a picker-side
    /// failure doesn't wipe the user's in-progress edits.
    @Published public var candidatesErrorMessage: String? = nil
    @Published public var isLoadingCandidates: Bool = false

    /// Live member selection state. Seeded from `fetchProjectMembers(projectId)` plus the
    /// owner id (owner is always selected and locked).
    @Published public var selectedMemberIds: Set<UUID> = []
    @Published public var memberSearch: String = ""

    // MARK: - Save state

    @Published public var isSaving: Bool = false
    @Published public var errorMessage: String? = nil

    private let client: SupabaseClient

    public init(client: SupabaseClient, project: Project) {
        self.client = client
        self.projectId = project.id
        self.ownerId = project.ownerId
        self.name = project.name
        self.descriptionText = project.description ?? ""
        self.status = project.status
        self.progress = max(0, min(100, project.progress))

        if let start = project.startDate {
            self.includeStartDate = true
            self.startDate = start
        } else {
            self.includeStartDate = false
            self.startDate = Date()
        }
        if let end = project.endDate {
            self.includeEndDate = true
            self.endDate = end
        } else {
            self.includeEndDate = false
            self.endDate = Date()
        }
    }

    // MARK: - Load picker state

    /// Parallel load:
    /// - active `profiles` (one batched fetch, ordered by `full_name` — matches Web)
    /// - current `project_members` user_ids for this project
    ///
    /// Owner id (if present) is forcibly included in `selectedMemberIds` to reflect the
    /// "owner is always a member" server invariant, even if the `project_members` row is
    /// temporarily missing for some reason.
    public func load() async {
        isLoadingCandidates = true
        candidatesErrorMessage = nil

        async let candidatesResult: Result<[ProjectMemberCandidate], Error> = runCandidatesFetch()
        async let membersResult: Result<[UUID], Error> = runMembersFetch()

        let (cResult, mResult) = await (candidatesResult, membersResult)

        switch cResult {
        case .success(let rows):
            self.candidates = rows
        case .failure(let error):
            self.candidates = []
            self.candidatesErrorMessage = error.localizedDescription
        }

        switch mResult {
        case .success(let ids):
            var set = Set(ids)
            if let ownerId { set.insert(ownerId) }
            self.selectedMemberIds = set
            self.originalMemberIds = set
        case .failure(let error):
            // Leave selection empty (plus owner) if member fetch failed; do NOT clobber
            // `errorMessage` — that is reserved for the save surface.
            var set: Set<UUID> = []
            if let ownerId { set.insert(ownerId) }
            self.selectedMemberIds = set
            self.originalMemberIds = set
            // Piggyback onto `candidatesErrorMessage` so the picker row can surface a single
            // soft banner. A separate key would add UI without adding information.
            if self.candidatesErrorMessage == nil {
                self.candidatesErrorMessage = error.localizedDescription
            }
        }

        isLoadingCandidates = false
    }

    private func runCandidatesFetch() async -> Result<[ProjectMemberCandidate], Error> {
        do {
            let rows: [ProjectMemberCandidate] = try await client
                .from("profiles")
                .select("id, full_name, avatar_url, role, department")
                .eq("status", value: "active")
                .order("full_name", ascending: true)
                .execute()
                .value
            return .success(rows)
        } catch {
            return .failure(error)
        }
    }

    private struct MembershipRow: Decodable {
        let userId: UUID
        enum CodingKeys: String, CodingKey { case userId = "user_id" }
    }

    private func runMembersFetch() async -> Result<[UUID], Error> {
        do {
            let rows: [MembershipRow] = try await client
                .from("project_members")
                .select("user_id")
                .eq("project_id", value: projectId)
                .execute()
                .value
            return .success(rows.map(\.userId))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Selection mutation

    /// Toggle a candidate's selected state. The owner row is locked — we short-circuit any
    /// attempt to flip the owner off so Web's `neq('user_id', ownerId)` invariant cannot be
    /// breached from the iOS side.
    public func toggleMember(_ id: UUID) {
        if let ownerId, id == ownerId { return }
        if selectedMemberIds.contains(id) {
            selectedMemberIds.remove(id)
        } else {
            selectedMemberIds.insert(id)
        }
    }

    /// Case-insensitive substring filter over `full_name` / `department` / `role`. Falls back
    /// to showing every candidate when the search text is empty.
    public var filteredCandidates: [ProjectMemberCandidate] {
        let trimmed = memberSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return candidates }
        return candidates.filter { candidate in
            if let name = candidate.fullName?.lowercased(), name.contains(trimmed) { return true }
            if let dept = candidate.department?.lowercased(), dept.contains(trimmed) { return true }
            if let role = candidate.role?.lowercased(), role.contains(trimmed) { return true }
            return false
        }
    }

    // MARK: - Validation

    /// Matches Web `editForm.name.trim()` non-empty check.
    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isSaveEnabled: Bool {
        !trimmedName.isEmpty && !isSaving
    }

    // MARK: - Save

    /// Mirrors Web `updateProject(id, updates)`:
    ///
    /// 1. `projects.update({...projectUpdates, updated_at: now}).eq('id', id).select(...).single()`
    /// 2. If members changed:
    ///    - `project_members.delete().eq('project_id', id).neq('user_id', ownerId)`
    ///    - `project_members.insert([...new members excluding owner, role: 'member'])`
    ///
    /// Owner is never removed. If the member picker fetch failed earlier (picker error) we
    /// still attempt to save project fields — but we skip the member rewrite step so a
    /// picker failure cannot accidentally wipe the existing `project_members` rows.
    ///
    /// Returns the refreshed `Project` so the caller can update its local state. Throws on
    /// failure of the projects.update round-trip; a later member-sync failure is surfaced on
    /// `errorMessage` but does NOT cause the whole save to be reported as failed — the
    /// project row was updated and the user sees a clear follow-up message.
    public func save() async -> Project? {
        guard isSaveEnabled else {
            errorMessage = "Project name is required."
            return nil
        }

        isSaving = true
        errorMessage = nil

        let clampedProgress = max(0, min(100, progress))
        let payload = ProjectUpdatePayload(
            name: trimmedName,
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: includeStartDate ? Self.dateOnlyFormatter.string(from: startDate) : nil,
            endDate: includeEndDate ? Self.dateOnlyFormatter.string(from: endDate) : nil,
            status: status.rawValue,
            progress: clampedProgress,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        do {
            let refreshed: Project = try await client
                .from("projects")
                .update(payload)
                .eq("id", value: projectId)
                .select()
                .single()
                .execute()
                .value

            // Members: only rewrite when candidates loaded successfully AND the selection
            // actually changed. This mirrors Web's `if (member_ids !== undefined)` semantics
            // while adding an iOS-side guard against a picker-fetch failure accidentally
            // wiping server membership state.
            if candidatesErrorMessage == nil, selectedMemberIds != originalMemberIds {
                do {
                    try await rewriteMembers()
                    originalMemberIds = selectedMemberIds
                } catch {
                    // Project row already saved — surface the member sync failure separately
                    // so the user knows the row updated but membership didn't.
                    errorMessage = "Project saved, but member update failed: \(error.localizedDescription)"
                }
            }

            isSaving = false
            return refreshed
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            return nil
        }
    }

    /// Delete-then-insert rewrite, matching Web:
    ///
    /// ```ts
    /// await supabase.from('project_members').delete()
    ///   .eq('project_id', id).neq('user_id', ownerId)
    /// const newMembers = (member_ids ?? [])
    ///   .filter(uid => uid !== ownerId)
    ///   .map(uid => ({ project_id: id, user_id: uid, role: 'member' }))
    /// if (newMembers.length > 0) await supabase.from('project_members').insert(newMembers)
    /// ```
    ///
    /// The delete clause is gated on `ownerId != nil`. If the project somehow has no owner
    /// (shouldn't happen in normal flow), we skip the delete to avoid nuking the last
    /// membership row — a conservative choice that matches Web's `if (ownerId)` guard.
    private func rewriteMembers() async throws {
        if let ownerId {
            _ = try await client
                .from("project_members")
                .delete()
                .eq("project_id", value: projectId)
                .neq("user_id", value: ownerId)
                .execute()
        }

        let newMembers = selectedMemberIds
            .filter { id in
                if let ownerId { return id != ownerId }
                return true
            }
            .map { uid in
                ProjectMemberInsert(project_id: projectId, user_id: uid, role: "member")
            }

        if !newMembers.isEmpty {
            _ = try await client
                .from("project_members")
                .insert(newMembers)
                .execute()
        }
    }

    // MARK: - Helpers

    /// `YYYY-MM-DD` formatter for `date` columns. Matches the wire format Web produces from
    /// `<input type="date">`, which the Postgres `date` type ingests cleanly.
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

// MARK: - Wire payloads

/// Encodable payload for `projects.update(...)`. Optional fields use `encodeIfPresent` via
/// Swift's synthesized encoder, which matches Web's `|| undefined` semantics — an empty /
/// untoggled field is OMITTED from the JSON body, so PostgREST leaves that column
/// untouched instead of setting it to NULL.
///
/// `startDate` / `endDate` are `String?` (YYYY-MM-DD) rather than `Date?` to keep the wire
/// shape predictable for `date` columns; the Supabase SDK's default `Date` encoder would
/// emit an ISO8601 timestamp.
private struct ProjectUpdatePayload: Encodable {
    let name: String
    let description: String?
    let startDate: String?
    let endDate: String?
    let status: String
    let progress: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case startDate = "start_date"
        case endDate = "end_date"
        case status
        case progress
        case updatedAt = "updated_at"
    }
}

/// Row shape for `project_members.insert([...])`. Column names match the Postgres schema
/// exactly; the encoder ships the raw `snake_case` keys.
private struct ProjectMemberInsert: Encodable {
    let project_id: UUID
    let user_id: UUID
    let role: String
}
