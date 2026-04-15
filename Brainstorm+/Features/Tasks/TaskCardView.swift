import SwiftUI

public struct TaskCardView: View {
    public let task: TaskModel
    var onToggleStatus: () -> Void
    
    public init(task: TaskModel, onToggleStatus: @escaping () -> Void = {}) {
        self.task = task
        self.onToggleStatus = onToggleStatus
    }
    
    private var isDone: Bool {
        task.status == .done
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Checkbox Actions
            Button(action: {
                HapticManager.shared.trigger(.success)
                onToggleStatus()
            }) {
                ZStack {
                    Circle()
                        .stroke(isDone ? Color.Brand.primary : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isDone {
                        Circle()
                            .fill(Color.Brand.primary)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(SquishyButtonStyle())
            .padding(.top, 2)
            
            // Content Content
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(task.title)
                        .font(.custom("Outfit-SemiBold", size: 16))
                        .foregroundColor(isDone ? Color.gray : Color.Brand.text)
                        .strikethrough(isDone, color: Color.gray)
                        .lineLimit(2)
                    
                    Spacer(minLength: 12)
                    
                    priorityIndicator(priority: task.priority)
                }
                
                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundColor(Color.gray)
                        .lineLimit(2)
                        .padding(.bottom, 4)
                }
                
                // Footer
                HStack {
                    statusTag(status: task.status)
                    
                    Spacer()
                    
                    if let dueDate = task.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                            Text(dueDate, style: .date)
                                .font(.custom("Inter-Medium", size: 12))
                        }
                        .foregroundColor(dueDate < Date() && !isDone ? Color.Brand.warning : Color.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.06))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(20)
        .background(Color.Brand.paper)
        // Apply Continuous Corner + md3-1 Tactical Elevation exactly tracking HIG vs CSS
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.03), lineWidth: 1)
        )
        // Dim the whole card gracefully if it's done
        .opacity(isDone ? 0.6 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDone)
    }
    
    @ViewBuilder
    private func priorityIndicator(priority: TaskModel.TaskPriority) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(priorityColor(priority))
                .frame(width: 6, height: 6)
            
            Text(priority.rawValue.uppercased())
                .font(.custom("Inter-Bold", size: 10))
                .foregroundColor(priorityColor(priority))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(priorityColor(priority).opacity(0.1))
        .clipShape(Capsule())
    }
    
    @ViewBuilder
    private func statusTag(status: TaskModel.TaskStatus) -> some View {
        let text = status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        Text(text)
            .font(.custom("Inter-Medium", size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.1))
            .foregroundColor(statusColor(status))
            .clipShape(Capsule())
    }
    
    private func priorityColor(_ priority: TaskModel.TaskPriority) -> Color {
        switch priority {
        case .low: return Color.gray
        case .medium: return Color.Brand.primary
        case .high: return Color.orange
        case .urgent: return Color.Brand.warning // Coral Orange
        }
    }
    
    private func statusColor(_ status: TaskModel.TaskStatus) -> Color {
        switch status {
        case .todo: return Color.gray
        case .inProgress: return Color.Brand.primary     // Azure Blue
        case .inReview: return Color.Brand.accent        // Mint Cyan
        case .done: return Color.green
        case .canceled: return Color.gray.opacity(0.5)
        }
    }
}
