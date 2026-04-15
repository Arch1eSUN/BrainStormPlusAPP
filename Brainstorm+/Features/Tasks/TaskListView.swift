import SwiftUI
import Combine

public struct TaskListView: View {
    @StateObject private var viewModel: TaskListViewModel
    @State private var selectedFilter: TaskFilter = .all
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
            return viewModel.tasks.filter { $0.status != .done && $0.status != .canceled }
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
                                        Button("Cancel Task", systemImage: "xmark.circle", role: .destructive) {
                                            Task { await viewModel.updateTaskStatus(task: task, newStatus: .canceled) }
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
                }
                .task {
                    await viewModel.fetchTasks()
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
                    // TODO: Open New Task Sheet
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
