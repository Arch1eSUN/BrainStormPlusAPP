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
}
