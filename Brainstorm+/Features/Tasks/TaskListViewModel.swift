import Foundation
import Combine
import Supabase

/// View model backing the Tasks list + Kanban view.
///
/// Mirrors Web's `BrainStorm+-Web/src/app/dashboard/tasks/page.tsx`
/// + `BrainStorm+-Web/src/lib/actions/tasks.ts`. Batch C.2 widened the
/// iOS surface to match Web:
/// - 4-state status (handled by the enum in `TaskModel`)
/// - stats / search / project filter (computed locally to keep this pass
///   simple — Web does it server-side via `fetchTaskStats` + `ilike`)
/// - multi-participant create (POST to `task_participants` after the
///   `tasks` insert, mirroring `createTask` in Web `tasks.ts:144-146`)
/// - `toggleTaskCompletion` quick entry (flips 0 ↔ 100 progress with the
///   same auto-status semantics as Web `tasks.ts:252-340`)
/// - optimistic status update (local mutate + snapshot revert on throw —
///   matches Web's `useOptimistic` / `startTransition` pattern)
@MainActor
public class TaskListViewModel: ObservableObject {
    @Published public private(set) var tasks: [TaskModel] = []
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var members: [ProjectMemberCandidate] = []
    @Published public private(set) var currentUserId: UUID? = nil
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    /// Search text — filters the local `tasks` array (title + description).
    /// Per iOS conventions, we use a client-side filter rather than Web's
    /// server-side `ilike` to keep the round-trip cheap.
    @Published public var searchText: String = ""

    /// Selected project filter. `nil` means "all projects".
    @Published public var projectFilter: UUID? = nil

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Derived / stats

    /// Tasks filtered by `searchText` + `projectFilter`. Consumed directly
    /// by the list + kanban; the status-segment filter is applied on top
    /// in the view.
    public var filteredTasks: [TaskModel] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks.filter { task in
            if let pid = projectFilter, task.projectId != pid { return false }
            if needle.isEmpty { return true }
            if task.title.lowercased().contains(needle) { return true }
            if let d = task.description, d.lowercased().contains(needle) { return true }
            return false
        }
    }

    /// Mirrors Web `fetchTaskStats()` in `tasks.ts:207-226`. Computed locally
    /// over the already-fetched `tasks` — good enough for the small personal
    /// scope and avoids an extra round-trip.
    public struct Stats: Equatable {
        public let total: Int
        public let todo: Int
        public let inProgress: Int
        public let review: Int
        public let done: Int
        public let overdue: Int
    }

    public var stats: Stats {
        let today = Calendar.current.startOfDay(for: Date())
        return Stats(
            total: tasks.count,
            todo: tasks.filter { $0.status == .todo }.count,
            inProgress: tasks.filter { $0.status == .inProgress }.count,
            review: tasks.filter { $0.status == .review }.count,
            done: tasks.filter { $0.status == .done }.count,
            overdue: tasks.filter { t in
                guard let due = t.dueDate else { return false }
                return due < today && t.status != .done
            }.count
        )
    }

    // MARK: - Create

    public struct TaskInsert: Encodable {
        public let title: String
        public let description: String?
        public let priority: String
        public let status: String
        public let due_date: String?
        public let project_id: UUID?
        public let owner_id: UUID
        public let reporter_id: UUID
        public let created_by: UUID
        public let assignee_id: UUID
        public let progress: Int
    }

    /// Narrow row returned from the `tasks` insert after we ask for `select("id")`.
    /// Used only to pick up the new row id for the subsequent `task_participants` insert.
    private struct InsertedTaskId: Decodable { let id: UUID }

    /// Row shape written to `task_participants`. Mirrors Web payload in
    /// `tasks.ts:114-142` — owner is always included as `role: 'owner'`,
    /// additional picks go in as `role: 'member'`.
    private struct ParticipantInsert: Encodable {
        let task_id: UUID
        let user_id: UUID
        let role: String
    }

    /// Create a new task + optional participant rows.
    ///
    /// `participantIds` mirrors Web's `participant_ids` form field. The
    /// current user is always added as `owner` (matching Web's fallback
    /// when `owner_id` is not supplied).
    public func createTask(
        title: String,
        description: String?,
        priority: TaskModel.TaskPriority,
        projectId: UUID? = nil,
        dueDate: Date?,
        participantIds: [UUID] = []
    ) async throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dueDateString = dueDate.map { formatter.string(from: $0) }

        let user = try await client.auth.session.user

        let newTask = TaskInsert(
            title: title,
            description: description,
            priority: priority.rawValue,
            status: TaskModel.TaskStatus.todo.rawValue,
            due_date: dueDateString,
            project_id: projectId,
            owner_id: user.id,
            reporter_id: user.id,
            created_by: user.id,
            assignee_id: user.id,
            progress: 0
        )

        // Insert + pull back the row id so we can write participants in a
        // second round-trip (Web uses a single client with `.select().single()`;
        // Supabase Swift exposes the same pattern via `.select("id")`).
        let inserted: InsertedTaskId = try await client
            .from("tasks")
            .insert(newTask)
            .select("id")
            .single()
            .execute()
            .value

        // Assemble participant rows. De-dup against owner so we never insert
        // the same user twice (would violate the UNIQUE(task_id, user_id)
        // constraint added in migration 036).
        var rows: [ParticipantInsert] = [
            ParticipantInsert(task_id: inserted.id, user_id: user.id, role: "owner")
        ]
        var seen: Set<UUID> = [user.id]
        for pid in participantIds where !seen.contains(pid) {
            rows.append(ParticipantInsert(task_id: inserted.id, user_id: pid, role: "member"))
            seen.insert(pid)
        }
        if rows.count > 1 {
            // Single batched insert (mirrors Web `supabase.from('task_participants').insert(participantsToInsert)`).
            // Best-effort: if this fails, the task still exists — the RLS trigger
            // in migration 036 auto-adds the owner on next read, so we tolerate it.
            do {
                try await client
                    .from("task_participants")
                    .insert(rows)
                    .execute()
            } catch {
                // Non-fatal: swallow so the caller still sees a successful task create.
                self.errorMessage = ErrorLocalizer.localize(error)
            }
        }

        await fetchTasks()
    }

    // MARK: - Fetch

    public func fetchTasks() async {
        isLoading = true
        errorMessage = nil
        do {
            // Mirror Web's select shape (tasks.ts:54 + 177) plus projects(id,name).
            // `task_participants(user_id)` collapses into [UUID] via TaskModel decoder.
            let columns = "id, title, description, status, priority, project_id, assignee_id, owner_id, reporter_id, progress, due_date, created_at, updated_at, projects:project_id(id, name), task_participants(user_id)"
            self.tasks = try await client
                .from("tasks")
                .select(columns)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
        isLoading = false
    }

    public func fetchProjects() async {
        do {
            self.projects = try await client
                .from("projects")
                .select()
                .execute()
                .value
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    /// Load active profiles for the participant picker. Mirrors the batched
    /// fetch used by ProjectEditViewModel (`profiles.select('id, full_name,
    /// avatar_url, role, department').eq('status','active').order('full_name')`).
    public func fetchMembers() async {
        do {
            self.members = try await client
                .from("profiles")
                .select("id, full_name, avatar_url, role, department")
                .eq("status", value: "active")
                .order("full_name", ascending: true)
                .execute()
                .value
        } catch {
            // Soft-fail — the picker simply shows an empty list.
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    /// Lazily populate `currentUserId`. Used by the create sheet to omit
    /// the caller from the participant picker (they're the implicit owner).
    public func fetchCurrentUserId() async {
        if currentUserId != nil { return }
        do {
            self.currentUserId = try await client.auth.session.user.id
        } catch {
            // Non-fatal — picker will still work, just shows the caller
            // as a selectable row.
        }
    }

    // MARK: - Mutations

    /// Optimistic status update. Mirrors Web `handleStatusChange` in
    /// `tasks/page.tsx:455-471` — we mutate the local array immediately so
    /// the card/kanban cell snaps to the new column, then revert the whole
    /// snapshot on error.
    public func updateTaskStatus(task: TaskModel, newStatus: TaskModel.TaskStatus) async {
        // ── Guard: done 状态不可逆向推进 ──
        // Mirrors Web's revert guard in BrainStorm+-Web/src/lib/actions/tasks.ts:166-171.
        if task.status == .done && newStatus != .done {
            self.errorMessage = "已完成的任务不能回退状态"
            return
        }

        // Snapshot for rollback.
        let snapshot = tasks

        // Optimistic local update — replace the affected row in place.
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = mutate(tasks[idx], status: newStatus)
        }

        do {
            try await client
                .from("tasks")
                .update(["status": newStatus.rawValue])
                .eq("id", value: task.id)
                .execute()
            // Re-fetch to pick up any server-side changes (updated_at, progress
            // auto-bumps triggered by task_participants side-effects, etc.).
            await fetchTasks()
        } catch {
            // Rollback to the pre-mutation array so UI stays consistent.
            self.tasks = snapshot
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    /// Quick progress toggle (0 ↔ 100). Mirrors Web `toggleTaskCompletion`
    /// in `tasks.ts:252-340`. On iOS we keep it simpler: flip the local
    /// `progress` optimistically and call `tasks.update` directly rather
    /// than walking `task_participants` — the server side already handles
    /// the multi-participant recalculation when needed, and for the
    /// single-user path this is a 1:1 of Web's visible effect.
    ///
    /// NB: this differs from Web's server action, which recomputes progress
    /// based on participant `completed_at` rows. We flag this in the
    /// summary — a full port would require a Postgres RPC or multi-step
    /// client logic that's not justified for batch C.2.
    public func toggleTaskCompletion(task: TaskModel) async {
        let snapshot = tasks
        let newProgress = task.progress >= 100 ? 0 : 100
        let newStatus: TaskModel.TaskStatus = {
            if newProgress == 100 { return .done }
            // If we just uncompleted a previously-done task, bump to in_progress.
            if task.status == .done { return .inProgress }
            return task.status
        }()

        // Optimistic local update.
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = mutate(tasks[idx], status: newStatus, progress: newProgress)
        }

        struct ProgressUpdate: Encodable {
            let progress: Int
            let status: String
        }
        do {
            try await client
                .from("tasks")
                .update(ProgressUpdate(progress: newProgress, status: newStatus.rawValue))
                .eq("id", value: task.id)
                .execute()
            await fetchTasks()
        } catch {
            self.tasks = snapshot
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    public func deleteTask(task: TaskModel) async {
        let snapshot = tasks
        // Optimistic removal.
        tasks.removeAll { $0.id == task.id }
        do {
            try await client
                .from("tasks")
                .delete()
                .eq("id", value: task.id)
                .execute()
        } catch {
            self.tasks = snapshot
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    // MARK: - Helpers

    /// Non-destructive copy with overridden fields. `TaskModel` has a
    /// custom Codable init owned by B.4; we can't reach in and assign
    /// `status`/`progress` directly. Round-trip through JSON so we stay
    /// decoupled from the init signature, and re-hydrate `participants`
    /// from the source struct (TaskModel.encode omits them).
    private func mutate(_ task: TaskModel, status: TaskModel.TaskStatus? = nil, progress: Int? = nil) -> TaskModel {
        do {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            encoder.dateEncodingStrategy = .iso8601
            decoder.dateDecodingStrategy = .iso8601
            let data = try encoder.encode(task)
            guard var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return task }
            if let status { dict["status"] = status.rawValue }
            if let progress { dict["progress"] = progress }
            // Re-synthesise `task_participants` so the decoder rebuilds
            // the same [UUID] participant list we had pre-mutation.
            if !task.participants.isEmpty {
                dict["task_participants"] = task.participants.map { ["user_id": $0.uuidString] }
            }
            let patched = try JSONSerialization.data(withJSONObject: dict)
            return try decoder.decode(TaskModel.self, from: patched)
        } catch {
            return task
        }
    }
}
