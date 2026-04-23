import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Batch C.4a — Picker view model shared by ProjectPickerView and
// TaskMultiSelectView.
//
// Web parity targets:
//   Projects list:
//     src/lib/actions/projects.ts → `fetchProjects({ status: 'active' })`
//     — RLS + `project_members` join gate what the current user can see.
//     iOS relies on RLS (no admin client) so the list is automatically
//     scoped to projects the user is a member of.
//   Tasks list:
//     src/lib/actions/tasks.ts → `fetchTasks()` filtered by project_id
//     when a project is picked. When no project is picked we pull tasks
//     where the user is either owner / reporter / assignee, or is in
//     `task_participants`. This mirrors Web's default task list scope
//     (tasks.ts:54-96) with one simplification: the Web code relies on
//     RLS + the view joins for participant visibility; iOS hits the
//     `task_participants` table and unions the ids client-side.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class ReportingPickerViewModel: ObservableObject {
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var tasks: [TaskModel] = []
    @Published public private(set) var isLoadingProjects: Bool = false
    @Published public private(set) var isLoadingTasks: Bool = false
    @Published public var errorMessage: String?

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // ──────────────────────────────────────────────────────────────
    // Projects
    // ──────────────────────────────────────────────────────────────

    /// 1:1 port of Web `fetchProjects({ status: 'active' })` scoped to
    /// projects the user is a member of. RLS on `projects` already
    /// filters non-members server-side, so we don't need the explicit
    /// `project_members` pre-lookup Web does in admin-client mode.
    public func loadProjects() async {
        isLoadingProjects = true
        defer { isLoadingProjects = false }
        do {
            let rows: [Project] = try await client
                .from("projects")
                .select()
                .eq("status", value: "active")
                .order("created_at", ascending: false)
                .execute()
                .value
            self.projects = rows
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Tasks
    // ──────────────────────────────────────────────────────────────

    /// Loads tasks scoped for the picker.
    ///
    /// • When `projectId` is set: filter by `project_id` (mirrors Web's
    ///   `tasks?project=<id>` query shape).
    /// • When `projectId` is nil: union of tasks where the current user
    ///   is owner/reporter/assignee, plus tasks the user participates in
    ///   via `task_participants`.
    public func loadTasks(for projectId: UUID?) async {
        isLoadingTasks = true
        defer { isLoadingTasks = false }
        do {
            let columns = "id, title, description, status, priority, project_id, assignee_id, owner_id, reporter_id, progress, due_date, created_at, updated_at, projects:project_id(id, name), task_participants(user_id)"

            if let projectId {
                let rows: [TaskModel] = try await client
                    .from("tasks")
                    .select(columns)
                    .eq("project_id", value: projectId.uuidString)
                    .order("created_at", ascending: false)
                    .execute()
                    .value
                self.tasks = rows
                return
            }

            // No project selected — union of ownership/reporter/assignee
            // rows and rows the user is a participant on. We run the two
            // queries in parallel and dedupe client-side by id.
            let session = try await client.auth.session
            let uid = session.user.id.uuidString

            async let direct: [TaskModel] = client
                .from("tasks")
                .select(columns)
                // owner OR reporter OR assignee — the Supabase Swift SDK
                // exposes `.or()` for combined predicates, same as JS.
                .or("owner_id.eq.\(uid),reporter_id.eq.\(uid),assignee_id.eq.\(uid)")
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value

            struct ParticipantRow: Decodable { let taskId: UUID
                enum CodingKeys: String, CodingKey { case taskId = "task_id" }
            }
            async let participantRows: [ParticipantRow] = client
                .from("task_participants")
                .select("task_id")
                .eq("user_id", value: uid)
                .execute()
                .value

            let (directTasks, partRows) = try await (direct, participantRows)
            let directIds = Set(directTasks.map { $0.id })
            let participantIds = Set(partRows.map { $0.taskId }).subtracting(directIds)

            var merged = directTasks
            if !participantIds.isEmpty {
                let extra: [TaskModel] = try await client
                    .from("tasks")
                    .select(columns)
                    .in("id", values: participantIds.map { $0.uuidString })
                    .execute()
                    .value
                merged.append(contentsOf: extra)
            }
            merged.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            self.tasks = merged
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }
}
