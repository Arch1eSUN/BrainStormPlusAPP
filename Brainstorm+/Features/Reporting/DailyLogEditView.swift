import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch B.1 — Daily log edit sheet.
//
// 1:1 surface port of the today-editor in
// `src/app/dashboard/daily/page.tsx`. We reuse the same fields:
// content, mood, progress, blockers, project_id, task_ids.
//
// Batch C.4a added the project picker + task multi-select UI (see
// ProjectPickerView.swift / TaskMultiSelectView.swift). Both are
// lazily loaded the first time the sheet opens.
// ══════════════════════════════════════════════════════════════════

public struct DailyLogEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var viewModel: ReportingViewModel
    @StateObject private var pickerVM: ReportingPickerViewModel

    private let existingLog: DailyLog?

    @State private var date: Date
    @State private var content: String
    @State private var mood: DailyLog.Mood
    @State private var progress: String
    @State private var blockers: String
    @State private var projectId: UUID?
    @State private var taskIds: [UUID]
    @State private var showDeleteConfirm = false
    @State private var showProjectPicker = false
    @State private var showTaskPicker = false

    public init(viewModel: ReportingViewModel, existingLog: DailyLog? = nil) {
        self.viewModel = viewModel
        self.existingLog = existingLog
        _pickerVM = StateObject(wrappedValue: ReportingPickerViewModel(client: supabase))
        _date = State(initialValue: existingLog?.date ?? Date())
        _content = State(initialValue: existingLog?.content ?? "")
        _mood = State(initialValue: existingLog?.mood ?? .good)
        _progress = State(initialValue: existingLog?.progress ?? "")
        _blockers = State(initialValue: existingLog?.blockers ?? "")
        _projectId = State(initialValue: existingLog?.projectId)
        _taskIds = State(initialValue: existingLog?.taskIds ?? [])
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("日期") {
                    // Edit is locked to the existing date so the upsert
                    // on (user_id, date) doesn't collide with a
                    // different day's log. New logs always default to
                    // today but the user can still pick a past date.
                    if existingLog == nil {
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                    } else {
                        HStack {
                            Text("日期")
                            Spacer()
                            Text(date, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("今日心情") {
                    Picker("心情", selection: $mood) {
                        ForEach(DailyLog.Mood.allCases) { m in
                            Text("\(m.emoji)  \(m.displayLabel)").tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("内容") {
                    TextEditor(text: $content)
                        .frame(minHeight: 140)
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("今天做了什么？遇到了什么？有什么想法？")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("关联项目") {
                    Button {
                        showProjectPicker = true
                    } label: {
                        HStack {
                            Text(projectLabel)
                                .foregroundStyle(projectId == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("关联任务") {
                    Button {
                        showTaskPicker = true
                    } label: {
                        HStack {
                            Text(taskLabel)
                                .foregroundStyle(taskIds.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    if !taskIds.isEmpty {
                        let selected = pickerVM.tasks.filter { taskIds.contains($0.id) }
                        ForEach(selected) { t in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                Text(t.title)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                Spacer()
                            }
                        }
                    }
                }

                Section("进展与阻塞") {
                    TextField("今日进展", text: $progress, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("遇到阻塞", text: $blockers, axis: .vertical)
                        .lineLimit(1...4)
                }

                if existingLog != nil {
                    Section {
                        Button("删除日志", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(existingLog == nil ? "新建日志" : "编辑日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text(existingLog == nil ? "保存" : "更新")
                    }
                    .disabled(isSaveDisabled)
                }
            }
            .overlay {
                if viewModel.isSaving {
                    ProgressView().controlSize(.large)
                }
            }
            .confirmationDialog(
                "确认删除这篇日志？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    Task {
                        if let log = existingLog {
                            await viewModel.deleteLog(log)
                            if viewModel.errorMessage == nil { dismiss() }
                        }
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("删除后无法恢复。")
            }
            .sheet(isPresented: $showProjectPicker) {
                ProjectPickerView(viewModel: pickerVM, selection: $projectId)
            }
            .sheet(isPresented: $showTaskPicker) {
                TaskMultiSelectView(
                    viewModel: pickerVM,
                    projectId: projectId,
                    selection: $taskIds
                )
            }
            .onChange(of: projectId) { _, newValue in
                // Task scope follows the project. Drop any selected
                // tasks that no longer match the new project; Web does
                // the same when the user flips the project dropdown.
                if let newValue {
                    taskIds.removeAll { id in
                        guard let t = pickerVM.tasks.first(where: { $0.id == id }) else { return false }
                        return t.projectId != newValue
                    }
                }
                Task { await pickerVM.loadTasks(for: newValue) }
            }
            .task {
                await pickerVM.loadProjects()
                await pickerVM.loadTasks(for: projectId)
            }
            .zyErrorBanner($viewModel.errorMessage)
        }
    }

    private var projectLabel: String {
        guard let pid = projectId else { return "选择项目（可选）" }
        if let p = pickerVM.projects.first(where: { $0.id == pid }) { return p.name }
        return "已选项目"
    }

    private var taskLabel: String {
        if taskIds.isEmpty { return "选择任务（可选）" }
        return "已关联 \(taskIds.count) 个任务"
    }

    private var isSaveDisabled: Bool {
        if viewModel.isSaving { return true }
        return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        let saved = await viewModel.saveLog(
            date: date,
            content: content,
            mood: mood,
            projectId: projectId,
            taskIds: taskIds,
            progress: progress.isEmpty ? nil : progress,
            blockers: blockers.isEmpty ? nil : blockers
        )
        if saved != nil {
            dismiss()
        }
    }
}
