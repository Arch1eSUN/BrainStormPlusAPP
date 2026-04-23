import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch C.4a — Multi-select task picker used by the daily-log edit
// sheet (daily_logs.task_ids) and available for future weekly-report
// task linkage if the schema adds one.
//
// Web parity:
//   src/app/dashboard/daily/page.tsx — task_ids is an array of UUIDs
//   chosen via a chip/toggle list, filtered by the currently-picked
//   project. When no project is selected, Web shows tasks the user
//   is involved with (owner/assignee/reporter/participant).
// ══════════════════════════════════════════════════════════════════

public struct TaskMultiSelectView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var viewModel: ReportingPickerViewModel

    private let projectId: UUID?
    @Binding private var selection: [UUID]
    @State private var searchText: String = ""

    public init(
        viewModel: ReportingPickerViewModel,
        projectId: UUID?,
        selection: Binding<[UUID]>
    ) {
        self.viewModel = viewModel
        self.projectId = projectId
        self._selection = selection
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜索任务", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section(projectId == nil ? "我参与的任务" : "该项目下的任务") {
                    if viewModel.isLoadingTasks && viewModel.tasks.isEmpty {
                        HStack {
                            ProgressView()
                            Text("加载中...").foregroundStyle(.secondary)
                        }
                    } else if filteredTasks.isEmpty {
                        Text(projectId == nil ? "暂无可关联的任务" : "该项目下没有任务")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredTasks) { task in
                            row(for: task)
                        }
                    }
                }
            }
            .navigationTitle("选择任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: projectId) {
                await viewModel.loadTasks(for: projectId)
            }
        }
    }

    // ── Derived ──────────────────────────────────────────────────

    private var filteredTasks: [TaskModel] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return viewModel.tasks }
        return viewModel.tasks.filter { t in
            if t.title.lowercased().contains(needle) { return true }
            if let d = t.description, d.lowercased().contains(needle) { return true }
            return false
        }
    }

    @ViewBuilder
    private func row(for task: TaskModel) -> some View {
        let isSelected = selection.contains(task.id)
        Button {
            if isSelected {
                selection.removeAll { $0 == task.id }
            } else {
                selection.append(task.id)
            }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        statusBadge(task.status)
                        if let name = task.project?.name, projectId == nil {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusBadge(_ status: TaskModel.TaskStatus) -> some View {
        let label: String = {
            switch status {
            case .todo: return "待办"
            case .inProgress: return "进行中"
            case .review: return "审阅中"
            case .done: return "已完成"
            }
        }()
        Text(label)
            .font(.caption2)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(Color.secondary.opacity(0.12), in: .capsule)
            .foregroundStyle(.secondary)
    }
}
