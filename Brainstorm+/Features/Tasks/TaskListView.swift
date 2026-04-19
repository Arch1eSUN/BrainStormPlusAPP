import SwiftUI
import Combine

public struct TaskListView: View {
    @StateObject private var viewModel: TaskListViewModel
    @State private var selectedFilter: TaskFilter = .all
    @State private var isShowingCreateTask = false
    @Namespace private var segmentAnimation
    
    enum TaskFilter: String, CaseIterable {
        case all = "All"
        case pending = "Pending"
        case done = "Done"
    }
    
    // Derived subset for the active filter
    private var filteredTasks: [TaskModel] {
        switch selectedFilter {
        case .all:
            return viewModel.tasks
        case .pending:
            return viewModel.tasks.filter { $0.status != .done  }
        case .done:
            return viewModel.tasks.filter { $0.status == .done }
        }
    }
    
    public init(viewModel: TaskListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Background tint (Warm hue)
                Color.Brand.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom Glassmorphic Header + Filter
                    headerAndFilterSection
                        .zIndex(10)
                    
                    if viewModel.isLoading && viewModel.tasks.isEmpty {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color.Brand.primary)
                        Spacer()
                    } else if filteredTasks.isEmpty {
                        Spacer()
                        emptyStateView
                        Spacer()
                    } else {
                        // Scrollable List
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                // Add vertical padding to avoid clipping the custom header shadow
                                Spacer().frame(height: 8)
                                
                                ForEach(filteredTasks) { task in
                                    TaskCardView(task: task) {
                                        // Quick toggle
                                        let newStatus: TaskModel.TaskStatus = (task.status == .done) ? .todo : .done
                                        Task { await viewModel.updateTaskStatus(task: task, newStatus: newStatus) }
                                    }
                                    .padding(.horizontal, 20)
                                    // Use HIG context menu for full management
                                    .contextMenu {
                                        if task.status != .done {
                                            Button("Mark as Done", systemImage: "checkmark.circle") {
                                                Task { await viewModel.updateTaskStatus(task: task, newStatus: .done) }
                                            }
                                        }
                                        if task.status != .inProgress {
                                            Button("In Progress", systemImage: "play.circle") {
                                                Task { await viewModel.updateTaskStatus(task: task, newStatus: .inProgress) }
                                            }
                                        }
                                        Button("Delete Task", systemImage: "trash", role: .destructive) {
                                            Task { await viewModel.deleteTask(task: task) }
                                        }
                                    }
                                }
                                
                                Spacer().frame(height: 100) // Bottom tab bar safe area
                            }
                        }
                    }
                }
                .navigationBarHidden(true)
                .refreshable {
                    HapticManager.shared.trigger(.soft)
                    await viewModel.fetchTasks()
                    await viewModel.fetchProjects()
                }
                .task {
                    await viewModel.fetchTasks()
                    await viewModel.fetchProjects()
                }
                .sheet(isPresented: $isShowingCreateTask) {
                    CreateTaskView(viewModel: viewModel)
                }
            }
        }
    }

    
    // MARK: - Subviews
    
    private var headerAndFilterSection: some View {
        VStack(spacing: 20) {
            // Main Title
            HStack {
                Text("My Tasks")
                    .font(.custom("Outfit-Bold", size: 32))
                    .foregroundColor(Color.Brand.text)
                
                Spacer()
                
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    isShowingCreateTask = true
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.Brand.primary)
                            .frame(width: 44, height: 44)
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: Color.Brand.primary.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(SquishyButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            // Custom Segmented Control with Liquid Glass style
            HStack(spacing: 8) {
                ForEach(TaskFilter.allCases, id: \.self) { filter in
                    let isSelected = selectedFilter == filter
                    
                    Text(filter.rawValue)
                        .font(.custom("Inter-Medium", size: 14))
                        .foregroundColor(isSelected ? Color.Brand.text : Color.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.Brand.paper)
                                    .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                                    .matchedGeometryEffect(id: "segment-bg", in: segmentAnimation)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            HapticManager.shared.trigger(.rigid)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedFilter = filter
                            }
                        }
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color.Brand.background.opacity(0.95))
        .background(.ultraThinMaterial)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.Brand.accent.opacity(0.08))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checklist")
                    .font(.system(size: 40))
                    .foregroundColor(Color.Brand.primary)
            }
            
            Text("No \(selectedFilter.rawValue.lowercased()) tasks found")
                .font(.custom("Outfit-SemiBold", size: 20))
                .foregroundColor(Color.Brand.text)
            
            Text("Take a break or create a new task to keep the momentum going.")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundColor(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
        // Card styling for empty state to give it boundary
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
        .padding(.horizontal, 24)
    }
}
import SwiftUI

public struct CreateTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TaskListViewModel
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var priority: TaskModel.TaskPriority = .medium
    @State private var projectId: UUID? = nil
    @State private var dueDate: Date = Date()
    @State private var includeDueDate: Bool = false
    
    @State private var isSubmitting: Bool = false
    @State private var submissionError: String? = nil
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Task Details").font(.custom("Inter-Medium", size: 14)).foregroundColor(.gray)) {
                    TextField("Task Title", text: $title)
                        .font(.custom("Inter-Regular", size: 16))
                    
                    TextField("Description (Optional)", text: $description, axis: .vertical)
                        .font(.custom("Inter-Regular", size: 16))
                        .lineLimit(3...6)
                }
                
                Section(header: Text("Configuration").font(.custom("Inter-Medium", size: 14)).foregroundColor(.gray)) {
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag(TaskModel.TaskPriority.low)
                        Text("Medium").tag(TaskModel.TaskPriority.medium)
                        Text("High").tag(TaskModel.TaskPriority.high)
                        Text("Urgent").tag(TaskModel.TaskPriority.urgent)
                    }
                    .font(.custom("Inter-Regular", size: 16))
                    
                    Picker("Project (Optional)", selection: $projectId) {
    Text("None").tag(nil as UUID?)
    ForEach(viewModel.projects) { project in
        Text(project.name).tag(project.id as UUID?)
    }
}
.font(.custom("Inter-Regular", size: 16))

Toggle("Set Due Date", isOn: $includeDueDate)
                        .font(.custom("Inter-Regular", size: 16))
                    
                    if includeDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    }
                }
                
                if let error = submissionError {
                    Section {
                        Text(error)
                            .font(.custom("Inter-Medium", size: 14))
                            .foregroundColor(Color.Brand.warning)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.trigger(.light)
                        dismiss()
                    }
                    .font(.custom("Inter-Medium", size: 16))
                    .foregroundColor(.gray)
                    .disabled(isSubmitting)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        submitTask()
                    }
                    .font(.custom("Inter-SemiBold", size: 16))
                    .foregroundColor(title.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : Color.Brand.primary)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        ProgressView()
                            .padding()
                            .background(Color.Brand.paper)
                            .cornerRadius(12)
                            .shadow(radius: 10)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func submitTask() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        isSubmitting = true
        submissionError = nil
        HapticManager.shared.trigger(.rigid)
        
        Task {
            do {
                try await viewModel.createTask(
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
                    priority: priority,
                projectId: projectId,
                    dueDate: includeDueDate ? dueDate : nil
                )
                HapticManager.shared.trigger(.success)
                dismiss()
            } catch {
                submissionError = error.localizedDescription
                HapticManager.shared.trigger(.error)
                isSubmitting = false
            }
        }
    }
}
