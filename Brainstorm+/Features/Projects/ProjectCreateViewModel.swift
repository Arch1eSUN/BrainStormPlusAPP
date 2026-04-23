import Foundation
import Combine
import Supabase

// MARK: - D.2a Project create foundation
//
// Mirrors Web `createProject(form)` in `BrainStorm+-Web/src/lib/actions/projects.ts`:
//
// ```ts
// const orgId = await getCurrentOrgId(guard.userId)
// const { data } = await supabase.from('projects').insert({
//   ...projectData,
//   owner_id: guard.userId,
//   org_id: orgId,
//   status: form.status || 'planning',
//   progress: 0,
// }).select('*, profiles:owner_id(full_name, avatar_url)').single()
//
// const allMemberIds = new Set([guard.userId, ...(member_ids ?? [])])
// const memberRows = Array.from(allMemberIds).map(uid => ({
//   project_id: data.id,
//   user_id: uid,
//   role: uid === guard.userId ? 'owner' : 'member',
// }))
// await supabase.from('project_members').insert(memberRows)
// ```
//
// Scope: editable fields match Web's create dialog — `name`, `description`, `start_date`,
// `end_date`, plus member picker. Status defaults to `planning`; `progress` defaults to 0.
// Web does NOT expose status / progress in its create dialog (lines 248-311 of page.tsx).

@MainActor
public class ProjectCreateViewModel: ObservableObject {
    // MARK: - Form state

    @Published public var name: String = ""
    @Published public var descriptionText: String = ""
    @Published public var includeStartDate: Bool = false
    @Published public var startDate: Date = Date()
    @Published public var includeEndDate: Bool = false
    @Published public var endDate: Date = Date()

    // MARK: - Member picker state

    @Published public var candidates: [ProjectMemberCandidate] = []
    @Published public var candidatesErrorMessage: String? = nil
    @Published public var isLoadingCandidates: Bool = false
    @Published public var selectedMemberIds: Set<UUID> = []
    @Published public var memberSearch: String = ""

    // MARK: - Save state

    @Published public var isSaving: Bool = false
    @Published public var errorMessage: String? = nil

    private let client: SupabaseClient
    private let currentUserId: UUID?

    public init(client: SupabaseClient, currentUserId: UUID?) {
        self.client = client
        self.currentUserId = currentUserId
    }

    // MARK: - Load picker candidates

    /// Mirrors Web `fetchAllUsersForPicker()` — one batched fetch of active profiles ordered
    /// by full_name. Failure surfaces on `candidatesErrorMessage` and does not block save.
    public func load() async {
        isLoadingCandidates = true
        candidatesErrorMessage = nil
        do {
            let rows: [ProjectMemberCandidate] = try await client
                .from("profiles")
                .select("id, full_name, avatar_url, role, department")
                .eq("status", value: "active")
                .order("full_name", ascending: true)
                .execute()
                .value
            self.candidates = rows
        } catch {
            self.candidates = []
            self.candidatesErrorMessage = ErrorLocalizer.localize(error)
        }
        isLoadingCandidates = false
    }

    public func toggleMember(_ id: UUID) {
        // Creator is implicitly owner; cannot be deselected.
        if let currentUserId, id == currentUserId { return }
        if selectedMemberIds.contains(id) {
            selectedMemberIds.remove(id)
        } else {
            selectedMemberIds.insert(id)
        }
    }

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

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isSaveEnabled: Bool {
        !trimmedName.isEmpty && !isSaving && currentUserId != nil
    }

    // MARK: - Save

    /// Two-step write that mirrors Web `createProject(form)`:
    /// 1. Resolve `org_id` via `profiles.select('org_id').eq('id', userId)`.
    /// 2. Insert into `projects` with `owner_id`, `org_id`, `status: 'planning'`, `progress: 0`.
    /// 3. Insert `project_members` rows (owner + selected members).
    public func save() async -> Project? {
        guard let ownerId = currentUserId else {
            errorMessage = "无法获取当前用户信息，请重新登录后再试。"
            return nil
        }
        guard isSaveEnabled else {
            errorMessage = "请填写项目名称。"
            return nil
        }

        isSaving = true
        errorMessage = nil

        do {
            // Step 1: resolve org_id. Matches `getCurrentOrgId(guard.userId)` on Web.
            let orgRows: [ProfileOrgRow] = try await client
                .from("profiles")
                .select("org_id")
                .eq("id", value: ownerId)
                .limit(1)
                .execute()
                .value
            guard let org = orgRows.first else {
                errorMessage = "无法获取组织信息。"
                isSaving = false
                return nil
            }

            // Step 2: insert project row.
            let payload = ProjectCreatePayload(
                name: trimmedName,
                description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: includeStartDate ? Self.dateOnlyFormatter.string(from: startDate) : nil,
                endDate: includeEndDate ? Self.dateOnlyFormatter.string(from: endDate) : nil,
                status: "planning",
                progress: 0,
                ownerId: ownerId,
                orgId: org.orgId
            )

            let created: Project = try await client
                .from("projects")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

            // Step 3: insert project_members rows. Owner always included; deduplicated.
            var allMemberIds = selectedMemberIds
            allMemberIds.insert(ownerId)
            let memberRows = allMemberIds.map { uid in
                ProjectMemberInsertRow(
                    project_id: created.id,
                    user_id: uid,
                    role: uid == ownerId ? "owner" : "member"
                )
            }
            if !memberRows.isEmpty {
                do {
                    _ = try await client
                        .from("project_members")
                        .insert(memberRows)
                        .execute()
                } catch {
                    // Project row succeeded; member insert did not. Surface a soft message
                    // but still return the created project so the list shows it immediately.
                    errorMessage = "项目已创建，但成员添加失败：\(ErrorLocalizer.localize(error))"
                }
            }

            isSaving = false
            return created
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
            isSaving = false
            return nil
        }
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

// MARK: - Wire payloads

/// `org_id` lookup row. `Profile` core model deliberately does NOT carry `org_id`, so a
/// narrow local DTO keeps the lookup tight. Same pattern 2.6 uses for the risk-action sync.
private struct ProfileOrgRow: Decodable {
    let orgId: UUID
    enum CodingKeys: String, CodingKey { case orgId = "org_id" }
}

/// Encodable payload for `projects.insert(...)`. Optional fields use `encodeIfPresent` via
/// the synthesized encoder so an omitted date / description is NOT sent to PostgREST — the
/// column stays at its DB default (NULL).
private struct ProjectCreatePayload: Encodable {
    let name: String
    let description: String?
    let startDate: String?
    let endDate: String?
    let status: String
    let progress: Int
    let ownerId: UUID
    let orgId: UUID

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case startDate = "start_date"
        case endDate = "end_date"
        case status
        case progress
        case ownerId = "owner_id"
        case orgId = "org_id"
    }
}

/// `project_members.insert([...])` row. Matches the Postgres schema exactly.
private struct ProjectMemberInsertRow: Encodable {
    let project_id: UUID
    let user_id: UUID
    let role: String
}
