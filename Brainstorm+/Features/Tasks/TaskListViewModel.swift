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

    /// 共享 yyyy-MM-dd formatter + ISO8601 formatter（避免每次调用都 alloc）
    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let iso8601Formatter = ISO8601DateFormatter()

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

    /// Row shape written to `task_participants` during toggleTaskCompletion
    /// auto-enrolment (Web `tasks.ts:268-281`). Shares the schema with
    /// `ParticipantInsert` but is a distinct struct so the dedicated
    /// select("id, user_id, completed_at") shape stays coupled to its read.
    private struct ParticipantUpsert: Encodable {
        let task_id: UUID
        let user_id: UUID
        let role: String
    }

    /// Select shape for `task_participants` rows read during toggle.
    /// Only fields needed for the multi-participant completion recompute.
    private struct ParticipantRow: Decodable {
        let id: UUID
        let user_id: UUID
        var completed_at: Date?
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
        let dueDateString = dueDate.map { Self.dueDateFormatter.string(from: $0) }

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

        // Activity log — 1:1 port of Web `writeActivityLog({ action: 'create_task', ... })`.
        await ActivityLogWriter.write(
            client: client,
            type: .task,
            action: "create_task",
            description: "创建了任务「\(title)」",
            entityType: "task",
            entityId: inserted.id
        )

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

            // Activity log — Web uses a generic `update_task` action for
            // any metadata mutation. Status change qualifies.
            await ActivityLogWriter.write(
                client: client,
                type: .task,
                action: "update_task",
                description: "更新了任务「\(task.title)」",
                entityType: "task",
                entityId: task.id
            )

            // Re-fetch to pick up any server-side changes (updated_at, progress
            // auto-bumps triggered by task_participants side-effects, etc.).
            await fetchTasks()
        } catch {
            // Rollback to the pre-mutation array so UI stays consistent.
            self.tasks = snapshot
            self.errorMessage = ErrorLocalizer.localize(error)
        }
    }

    /// Multi-participant completion toggle — 1:1 port of Web
    /// `toggleTaskCompletion` in `BrainStorm+-Web/src/lib/actions/tasks.ts:252-340`.
    ///
    /// Flow (7 steps, exactly matching Web):
    ///  1. Fetch all rows from `task_participants` for this task.
    ///  2. Find the current user's participant row; if missing, insert one
    ///     with role='member' (auto-enrolment for creators/owners).
    ///  3. Toggle that row's `completed_at` (null ↔ now()).
    ///  4. Recompute progress = round(completedCount / total * 100).
    ///  5. If progress == 100 → tasks.status = 'done'.
    ///     If uncompleted and current status was 'done' → bump to 'in_progress'.
    ///  6. Update the `tasks` row (progress + optional status).
    ///  7. Write an activity_log entry describing the action.
    ///
    /// Returns `true` on success. On failure we revert optimistic state,
    /// emit `errorMessage`, and fire a warning haptic. On success we emit
    /// a selection haptic (toggle is not a terminal action).
    @discardableResult
    public func toggleTaskCompletion(_ taskId: UUID) async -> Bool {
        // Snapshot the current tasks array so we can revert on error.
        // If the row isn't in our cache (stale state), we still proceed —
        // the server is the source of truth.
        let snapshot = tasks

        do {
            let userId = try await client.auth.session.user.id

            // ── Step 1: fetch participants ───────────────────────────
            var participants: [ParticipantRow] = try await client
                .from("task_participants")
                .select("id, user_id, completed_at")
                .eq("task_id", value: taskId)
                .execute()
                .value

            // ── Step 2: find / create current user's row ─────────────
            var userParticipantIndex = participants.firstIndex(where: { $0.user_id == userId })
            if userParticipantIndex == nil {
                let inserted: ParticipantRow = try await client
                    .from("task_participants")
                    .insert(ParticipantUpsert(
                        task_id: taskId,
                        user_id: userId,
                        role: "member"
                    ))
                    .select("id, user_id, completed_at")
                    .single()
                    .execute()
                    .value
                participants.append(inserted)
                userParticipantIndex = participants.count - 1
            }
            guard let idx = userParticipantIndex else { return false }
            var userParticipant = participants[idx]

            // ── Step 3: toggle completed_at ──────────────────────────
            let isCompleted = userParticipant.completed_at != nil
            let completedAtDate: Date? = isCompleted ? nil : Date()
            // Pre-format to ISO-8601 for Supabase (matches the pattern
            // used elsewhere in the app, e.g. ProjectEditViewModel:259).
            let completedAtString: String? = completedAtDate.map {
                Self.iso8601Formatter.string(from: $0)
            }

            struct CompletedAtUpdate: Encodable {
                let completed_at: String?
            }
            try await client
                .from("task_participants")
                .update(CompletedAtUpdate(completed_at: completedAtString))
                .eq("id", value: userParticipant.id)
                .execute()

            // Mirror local state so the progress calc sees the latest value.
            userParticipant.completed_at = completedAtDate
            participants[idx] = userParticipant

            // ── Step 4: recompute progress ───────────────────────────
            let total = participants.count
            let completedCount = participants.filter { $0.completed_at != nil }.count
            let progress = total > 0 ? Int((Double(completedCount) / Double(total) * 100).rounded()) : 0

            // ── Step 5: decide status transition ─────────────────────
            var newStatus: TaskModel.TaskStatus? = nil
            if progress == 100 {
                newStatus = .done
            } else if completedAtDate == nil {
                // Just uncompleted — if the task was previously 'done',
                // roll it back to in_progress. Fetch current status to match
                // Web semantics (it doesn't trust its local copy either).
                struct StatusRow: Decodable { let status: String }
                let current: StatusRow? = try? await client
                    .from("tasks")
                    .select("status")
                    .eq("id", value: taskId)
                    .single()
                    .execute()
                    .value
                if current?.status == TaskModel.TaskStatus.done.rawValue {
                    newStatus = .inProgress
                }
            }

            // ── Step 6: update tasks row ─────────────────────────────
            if let newStatus {
                struct ProgressAndStatus: Encodable {
                    let progress: Int
                    let status: String
                }
                try await client
                    .from("tasks")
                    .update(ProgressAndStatus(progress: progress, status: newStatus.rawValue))
                    .eq("id", value: taskId)
                    .execute()
            } else {
                struct ProgressOnly: Encodable { let progress: Int }
                try await client
                    .from("tasks")
                    .update(ProgressOnly(progress: progress))
                    .eq("id", value: taskId)
                    .execute()
            }

            // Local patch — avoid full refetch, matching the previous
            // optimistic-feel of the list/kanban cells.
            if let rowIdx = tasks.firstIndex(where: { $0.id == taskId }) {
                let effectiveStatus = newStatus ?? tasks[rowIdx].status
                tasks[rowIdx] = mutate(tasks[rowIdx], status: effectiveStatus, progress: progress)
            }

            // ── Step 7: activity_log ─────────────────────────────────
            let description = (completedAtDate != nil)
                ? "完成了分配的任务部分"
                : "撤销了任务完成状态"
            await ActivityLogWriter.write(
                client: client,
                type: .task,
                action: "task_updated",
                description: description,
                entityType: "task",
                entityId: taskId
            )

            Haptic.selection()
            return true
        } catch {
            self.tasks = snapshot
            self.errorMessage = ErrorLocalizer.localize(error)
            Haptic.warning()
            return false
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

            // Activity log — record the delete with the captured title
            // (the row is gone by now; we can't re-read it).
            await ActivityLogWriter.write(
                client: client,
                type: .task,
                action: "delete_task",
                description: "删除了任务「\(task.title)」",
                entityType: "task",
                entityId: task.id
            )
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
