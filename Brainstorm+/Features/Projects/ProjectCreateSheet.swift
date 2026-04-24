import SwiftUI
import Supabase

// MARK: - D.2a Project create sheet
//
// Presents the create-project form. Mirrors Web's "新建项目" dialog in
// `BrainStorm+-Web/src/app/dashboard/projects/page.tsx` (lines 240-321):
// - Project name, description
// - Start / end dates
// - Member picker (multi-select)
//
// Status / progress are NOT exposed here; they default server-side to `planning` / `0` in
// `createProject(form)`. Edit flow (`ProjectEditSheet`) is where status / progress live.

public struct ProjectCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ProjectCreateViewModel

    /// Fired after a successful create so the presenting view can reload the list.
    private let onCreated: (Project) -> Void

    public init(client: SupabaseClient, currentUserId: UUID?, onCreated: @escaping (Project) -> Void) {
        _viewModel = StateObject(wrappedValue: ProjectCreateViewModel(client: client, currentUserId: currentUserId))
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            Form {
                detailsSection
                scheduleSection
                membersSection

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(BsTypography.caption)
                            .foregroundColor(BsColor.danger)
                    }
                }
            }
            .navigationTitle("新建项目")
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
                    Button("创建") {
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
        let isSelected = viewModel.selectedMemberIds.contains(candidate.id)
        return Button {
            viewModel.toggleMember(candidate.id)
        } label: {
            HStack(spacing: BsSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? BsColor.brandAzure : BsColor.inkMuted)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayName)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundColor(BsColor.ink)
                        .lineLimit(1)
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
        .disabled(viewModel.isSaving)
    }

    private func secondaryLine(candidate: ProjectMemberCandidate) -> String? {
        var parts: [String] = []
        if let dept = candidate.department, !dept.isEmpty { parts.append(dept) }
        if let role = candidate.role, !role.isEmpty { parts.append(role) }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(BsTypography.caption)
            .foregroundColor(BsColor.inkMuted)
    }

    private func submit() async {
        if let created = await viewModel.save() {
            onCreated(created)
            dismiss()
        }
        // Failure surfaces in the form via `errorMessage`; sheet stays open.
    }
}
