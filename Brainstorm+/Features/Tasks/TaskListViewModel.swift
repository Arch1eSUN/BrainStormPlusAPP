import Foundation
import Combine
import Supabase

@MainActor
public class TaskListViewModel: ObservableObject {
    @Published public var tasks: [TaskModel] = []
    @Published public var projects: [Project] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let client: SupabaseClient
    
    public init(client: SupabaseClient) {
        self.client = client
    }
    
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

public func createTask(title: String, description: String?, priority: TaskModel.TaskPriority, projectId: UUID? = nil, dueDate: Date?) async throws {
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
        
        try await client
            .from("tasks")
            .insert(newTask)
            .execute()
            
        await fetchTasks()
    }
    
public func fetchTasks() async {
        isLoading = true
        errorMessage = nil
        do {
            self.tasks = try await client
                .from("tasks")
                .select()
                .execute()
                .value
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    public func fetchProjects() async {
        isLoading = true
        do {
            self.projects = try await client
                .from("projects")
                .select()
                .execute()
                .value
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    public func updateTaskStatus(task: TaskModel, newStatus: TaskModel.TaskStatus) async {
        do {
            try await client
                .from("tasks")
                .update(["status": newStatus.rawValue])
                .eq("id", value: task.id)
                .execute()
            await fetchTasks()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func deleteTask(task: TaskModel) async {
        do {
            try await client
                .from("tasks")
                .delete()
                .eq("id", value: task.id)
                .execute()
            await fetchTasks()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
