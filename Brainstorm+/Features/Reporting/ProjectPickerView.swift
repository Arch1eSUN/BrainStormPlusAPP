import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch C.4a — Single-select project picker used by the daily-log
// and weekly-report edit sheets.
//
// Web parity:
//   src/app/dashboard/daily/page.tsx — a single <select> bound to
//   form.project_id.
//   src/app/dashboard/weekly/page.tsx — project_ids is multi-select
//   (chip toggles). For daily logs Web uses single-select because
//   `daily_logs.project_id` is scalar; weekly reports use multi.
//
// This view covers the single-select case. Weekly multi-select is
// implemented inline in WeeklyReportEditView via the chip list, since
// it's just a set toggle — extracting a shared multi-select project
// view would be over-engineering for batch C.4a.
// ══════════════════════════════════════════════════════════════════

public struct ProjectPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var viewModel: ReportingPickerViewModel

    @Binding private var selection: UUID?

    public init(viewModel: ReportingPickerViewModel, selection: Binding<UUID?>) {
        self.viewModel = viewModel
        self._selection = selection
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selection = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("不关联项目")
                            Spacer()
                            if selection == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("我的项目") {
                    if viewModel.isLoadingProjects && viewModel.projects.isEmpty {
                        HStack {
                            ProgressView()
                            Text("加载中...").foregroundStyle(.secondary)
                        }
                    } else if viewModel.projects.isEmpty {
                        Text("暂无可关联的项目")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.projects) { project in
                            Button {
                                selection = project.id
                                dismiss()
                            } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.name)
                                            .foregroundStyle(.primary)
                                        if let desc = project.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if selection == project.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("选择项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                if viewModel.projects.isEmpty {
                    await viewModel.loadProjects()
                }
            }
        }
    }
}
