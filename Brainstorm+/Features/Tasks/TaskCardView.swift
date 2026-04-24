import SwiftUI

public struct TaskCardView: View {
    public let task: TaskModel
    /// Tap on the checkmark circle. Historically this toggled status
    /// todo ↔ done. Batch C.2 keeps the same binding but the caller
    /// wires this up to `toggleTaskCompletion` (0↔100 progress) to
    /// match Web's quick-complete entry.
    var onToggleStatus: () -> Void

    public init(task: TaskModel, onToggleStatus: @escaping () -> Void = {}) {
        self.task = task
        self.onToggleStatus = onToggleStatus
    }

    private var isDone: Bool {
        task.status == .done
    }

    public var body: some View {
        BsContentCard(padding: .none) {
            cardBody
        }
        .opacity(isDone ? 0.6 : 1.0)
        .animation(BsMotion.Anim.overshoot, value: isDone)
    }

    @ViewBuilder
    private var cardBody: some View {
        HStack(alignment: .top, spacing: BsSpacing.lg) {
            // Checkbox / quick-complete button.
            Button(action: {
                Haptic.success()
                onToggleStatus()
            }) {
                ZStack {
                    Circle()
                        .stroke(isDone ? BsColor.brandAzure : BsColor.inkFaint, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isDone {
                        Circle()
                            .fill(BsColor.brandAzure)
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

            // Content
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                HStack(alignment: .top) {
                    Text(task.title)
                        .font(BsTypography.cardTitle)
                        .foregroundColor(isDone ? BsColor.inkMuted : BsColor.ink)
                        .strikethrough(isDone, color: BsColor.inkMuted)
                        .lineLimit(2)

                    Spacer(minLength: BsSpacing.md)

                    priorityIndicator(priority: task.priority)
                }

                // Project tag (mirrors Web's inline folder-kanban pill).
                if let project = task.project {
                    HStack(spacing: BsSpacing.xs) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9))
                        Text(project.name)
                            .font(BsTypography.inter(11, weight: "Medium"))
                    }
                    .foregroundColor(BsColor.brandAzure.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(BsColor.brandAzure.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.xs, style: .continuous))
                }

                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .font(BsTypography.bodySmall)
                        .foregroundColor(BsColor.inkMuted)
                        .lineLimit(2)
                        .padding(.bottom, BsSpacing.xs)
                }

                // Progress bar (mirrors Web tasks/page.tsx:60-68).
                if task.progress > 0 || task.status != .todo {
                    VStack(alignment: .leading, spacing: BsSpacing.xs) {
                        HStack {
                            Text("进度")
                                .font(BsTypography.inter(10, weight: "Regular"))
                                .foregroundColor(BsColor.inkMuted)
                            Spacer()
                            Text("\(task.progress)%")
                                .font(BsTypography.inter(10, weight: "Medium"))
                                .foregroundColor(BsColor.inkMuted)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(BsColor.inkFaint.opacity(0.35))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(BsColor.success)
                                    .frame(width: proxy.size.width * CGFloat(task.progress) / 100, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                // Footer
                HStack {
                    statusTag(status: task.status)

                    Spacer()

                    if let dueDate = task.dueDate {
                        HStack(spacing: BsSpacing.xs) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                            Text(dueDate, style: .date)
                                .font(BsTypography.captionSmall)
                        }
                        .foregroundColor(dueDate < Date() && !isDone ? BsColor.brandCoral : BsColor.inkMuted)
                        .padding(.horizontal, BsSpacing.sm)
                        .padding(.vertical, BsSpacing.xs)
                        .background(BsColor.surfaceSecondary.opacity(0.6))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(BsSpacing.lg + 4)
    }

    @ViewBuilder
    private func priorityIndicator(priority: TaskModel.TaskPriority) -> some View {
        HStack(spacing: BsSpacing.xs) {
            Circle()
                .fill(priority.tint)
                .frame(width: 6, height: 6)

            Text(priority.cnLabel)
                .font(BsTypography.meta)
                .foregroundColor(priority.tint)
        }
        .padding(.horizontal, BsSpacing.sm)
        .padding(.vertical, BsSpacing.xs)
        .background(priority.tint.opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func statusTag(status: TaskModel.TaskStatus) -> some View {
        Text(status.cnLabel)
            .font(BsTypography.captionSmall)
            .padding(.horizontal, BsSpacing.md - 2)
            .padding(.vertical, BsSpacing.xs)
            .background(status.tint.opacity(0.1))
            .foregroundColor(status.tint)
            .clipShape(Capsule())
    }
}

/// Compact version used inside Kanban columns where horizontal space is
/// tight and the status column already encodes the state.
public struct TaskKanbanCardView: View {
    public let task: TaskModel
    /// Tapping the title opens a status menu; this callback is the single
    /// exit point for status changes from the Kanban.
    var onChangeStatus: (TaskModel.TaskStatus) -> Void
    var onToggleComplete: () -> Void
    var onDelete: () -> Void

    public init(
        task: TaskModel,
        onChangeStatus: @escaping (TaskModel.TaskStatus) -> Void,
        onToggleComplete: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        self.task = task
        self.onChangeStatus = onChangeStatus
        self.onToggleComplete = onToggleComplete
        self.onDelete = onDelete
    }

    public var body: some View {
        BsCard(variant: .flat, padding: .small) {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                HStack(alignment: .top) {
                    Text(task.title)
                        .font(BsTypography.inter(14, weight: "SemiBold"))
                        .foregroundColor(BsColor.ink)
                        .lineLimit(2)
                    Spacer(minLength: BsSpacing.sm)
                    Text(task.priority.cnLabel)
                        .font(BsTypography.inter(9, weight: "Bold"))
                        .foregroundColor(task.priority.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(task.priority.tint.opacity(0.1))
                        .clipShape(Capsule())
                }

                if let project = task.project {
                    Text(project.name)
                        .font(BsTypography.inter(10, weight: "Medium"))
                        .foregroundColor(BsColor.brandAzure.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BsColor.brandAzure.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xs, style: .continuous))
                }

                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .font(BsTypography.inter(12, weight: "Regular"))
                        .foregroundColor(BsColor.inkMuted)
                        .lineLimit(2)
                }

                // Mini progress bar.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(BsColor.inkFaint.opacity(0.35))
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(BsColor.success)
                            .frame(width: proxy.size.width * CGFloat(task.progress) / 100)
                    }
                }
                .frame(height: 3)

                HStack(spacing: 6) {
                    if let due = task.dueDate {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(due, style: .date)
                                .font(BsTypography.inter(10, weight: "Medium"))
                        }
                        .foregroundColor(BsColor.inkMuted)
                    }
                    Spacer()
                    // Participant count (if >0) — a small 1:1 port of Web's
                    // avatar group where we don't have the full profile join.
                    if !task.participants.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9))
                            Text("\(task.participants.count)")
                                .font(BsTypography.inter(10, weight: "Medium"))
                        }
                        .foregroundColor(BsColor.inkMuted)
                    }
                }
            }
        }
        .contextMenu {
            // Status switcher — one entry per state (disabled for the
            // current state, so the menu always shows 4 rows).
            ForEach([TaskModel.TaskStatus.todo, .inProgress, .review, .done], id: \.self) { s in
                Button {
                    onChangeStatus(s)
                } label: {
                    Label(s.cnLabel, systemImage: s == task.status ? "checkmark" : "")
                }
                .disabled(s == task.status)
            }
            Divider()
            Button {
                onToggleComplete()
            } label: {
                Label(task.progress >= 100 ? "撤销完成" : "标记完成", systemImage: "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
