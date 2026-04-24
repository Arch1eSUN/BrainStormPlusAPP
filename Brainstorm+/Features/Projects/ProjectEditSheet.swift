import SwiftUI
import Supabase

// MARK: - 1.9 Project edit sheet
//
// Native edit entry for an existing project. Mirrors Web's edit dialog in
// `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` `showEdit` panel and its save handler
// `handleUpdateProject()` which calls `updateProject(...)` + `fetchProjectMembers(...)`.
//
// Scope (Round 1.9 foundation):
// - editable fields: `name`, `description`, `start_date`, `end_date`, `status`, `progress`
// - member picker: toggle selection across active profiles; owner row locked
// - save: issues real Supabase update; on success calls `onSaved(refreshedProject)` so
//   the presenting view can reload list / detail state.
public struct ProjectEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ProjectEditViewModel

    /// Called with the server-refreshed `Project` after a successful save. The caller uses
    /// this to re-run its own fetches (list reload, detail reload) — the sheet itself does
    /// not try to mutate any parent view model directly.
    private let onSaved: (Project) -> Void

    public init(client: SupabaseClient, project: Project, onSaved: @escaping (Project) -> Void) {
        _viewModel = StateObject(wrappedValue: ProjectEditViewModel(client: client, project: project))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                detailsSection
                scheduleSection
                statusProgressSection
                membersSection

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(BsTypography.caption)
                            .foregroundColor(BsColor.danger)
                    }
                }
            }
            .navigationTitle("编辑项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .font(.system(.callout, weight: .medium))
                    .foregroundColor(BsColor.inkMuted)
                    .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        Task { await submit() }
                    }
                    .font(.system(.callout, weight: .semibold))
                    .foregroundColor(viewModel.isSaveEnabled ? BsColor.brandAzure : BsColor.inkMuted)
                    .disabled(!viewModel.isSaveEnabled)
                }
            }
            .overlay {
                if viewModel.isSaving {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        ProgressView()
                            .padding()
                            .background(BsColor.surfacePrimary)
                            .cornerRadius(BsRadius.md)
                            .shadow(radius: 8)
                    }
                }
            }
            .task {
                await viewModel.load()
            }
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section(header: sectionHeader("项目信息")) {
            TextField("项目名称", text: $viewModel.name)
                .font(.system(.callout))
                .disabled(viewModel.isSaving)

            TextField(
                "简要描述项目目标（可选）",
                text: $viewModel.descriptionText,
                axis: .vertical
            )
            .font(.system(.callout))
            .lineLimit(3...6)
            .disabled(viewModel.isSaving)
        }
    }

    private var scheduleSection: some View {
        Section(header: sectionHeader("日期")) {
            Toggle("设置开始日期", isOn: $viewModel.includeStartDate)
                .font(BsTypography.body)
                .disabled(viewModel.isSaving)
            if viewModel.includeStartDate {
                DatePicker("开始日期", selection: $viewModel.startDate, displayedComponents: .date)
                    .font(BsTypography.body)
                    .disabled(viewModel.isSaving)
            }

            Toggle("设置结束日期", isOn: $viewModel.includeEndDate)
                .font(BsTypography.body)
                .disabled(viewModel.isSaving)
            if viewModel.includeEndDate {
                DatePicker("结束日期", selection: $viewModel.endDate, displayedComponents: .date)
                    .font(BsTypography.body)
                    .disabled(viewModel.isSaving)
            }

            // Parity note — Web only SENDS a date field when it's filled, so an untoggled date
            // here leaves the column untouched on the server (rather than clearing it). This
            // is intentional Round 1.9 parity with Web, not a bug.
            Text("关闭日期开关仅从本次保存中省略该字段，服务器上的已有值不会被清除。")
                .font(BsTypography.captionSmall)
                .foregroundColor(BsColor.inkMuted)
        }
    }

    private var statusProgressSection: some View {
        Section(header: sectionHeader("状态与进度")) {
            Picker("状态", selection: $viewModel.status) {
                Text("规划中").tag(Project.ProjectStatus.planning)
                Text("进行中").tag(Project.ProjectStatus.active)
                Text("暂停").tag(Project.ProjectStatus.onHold)
                Text("已完成").tag(Project.ProjectStatus.completed)
                Text("归档").tag(Project.ProjectStatus.archived)
            }
            .font(BsTypography.body)
            .disabled(viewModel.isSaving)

            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                HStack {
                    Text("进度")
                        .font(BsTypography.body)
                    Spacer()
                    Text("\(viewModel.progress)%")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundColor(BsColor.brandAzure)
                }
                Slider(
                    value: Binding(
                        get: { Double(viewModel.progress) },
                        set: { viewModel.progress = Int($0.rounded()) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .tint(BsColor.brandAzure)
                .disabled(viewModel.isSaving)
            }
            .padding(.vertical, BsSpacing.xs)
        }
    }

    private var membersSection: some View {
        Section(header: membersSectionHeader) {
            if let message = viewModel.candidatesErrorMessage {
                HStack(spacing: BsSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(BsColor.warning)
                    Text("成员加载失败：\(message)")
                        .font(.system(.caption))
                        .foregroundColor(BsColor.warning)
                        .lineLimit(3)
                }
            } else if viewModel.isLoadingCandidates {
                HStack(spacing: BsSpacing.sm) {
                    ProgressView()
                    Text("正在加载成员…")
                        .font(BsTypography.bodySmall)
                        .foregroundColor(BsColor.inkMuted)
                }
            } else if viewModel.candidates.isEmpty {
                Text("暂无可选成员。")
                    .font(BsTypography.bodySmall)
                    .foregroundColor(BsColor.inkMuted)
            } else {
                TextField("搜索成员", text: $viewModel.memberSearch)
                    .font(BsTypography.body)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isSaving)

                ForEach(viewModel.filteredCandidates) { candidate in
                    memberRow(candidate: candidate)
                }
            }
        }
    }

    private var membersSectionHeader: some View {
        HStack {
            sectionHeader("项目成员")
            Spacer()
            Text("已选 \(viewModel.selectedMemberIds.count) 人")
                .font(BsTypography.captionSmall)
                .foregroundColor(BsColor.inkMuted)
                .textCase(nil)
        }
    }

    private func memberRow(candidate: ProjectMemberCandidate) -> some View {
        let isOwner = viewModel.ownerId == candidate.id
        let isSelected = viewModel.selectedMemberIds.contains(candidate.id)
        return Button {
            viewModel.toggleMember(candidate.id)
        } label: {
            HStack(spacing: BsSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? BsColor.brandAzure : BsColor.inkMuted)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(candidate.displayName)
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundColor(BsColor.ink)
                            .lineLimit(1)
                        if isOwner {
                            Text("所有者")
                                .font(BsTypography.meta)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BsColor.brandAzureLight)
                                .foregroundColor(BsColor.brandAzure)
                                .clipShape(Capsule())
                        }
                    }
                    if let secondary = secondaryLine(candidate: candidate) {
                        Text(secondary)
                            .font(BsTypography.captionSmall)
                            .foregroundColor(BsColor.inkMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOwner || viewModel.isSaving)
        .opacity(isOwner ? 0.85 : 1.0)
    }

    private func secondaryLine(candidate: ProjectMemberCandidate) -> String? {
        var parts: [String] = []
        if let dept = candidate.department, !dept.isEmpty { parts.append(dept) }
        if let role = candidate.role, !role.isEmpty { parts.append(role) }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(BsTypography.caption)
            .foregroundColor(BsColor.inkMuted)
    }

    private func submit() async {
        if let refreshed = await viewModel.save() {
            onSaved(refreshed)
            dismiss()
        }
        // If save failed, `errorMessage` is already set on the VM and rendered in the form.
    }
}
