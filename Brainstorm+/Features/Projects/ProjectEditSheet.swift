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
                            .font(.custom("Inter-Medium", size: 13))
                            .foregroundColor(Color.Brand.warning)
                    }
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("Inter-Medium", size: 16))
                    .foregroundColor(.gray)
                    .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await submit() }
                    }
                    .font(.custom("Inter-SemiBold", size: 16))
                    .foregroundColor(viewModel.isSaveEnabled ? Color.Brand.primary : .gray)
                    .disabled(!viewModel.isSaveEnabled)
                }
            }
            .overlay {
                if viewModel.isSaving {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        ProgressView()
                            .padding()
                            .background(Color.Brand.paper)
                            .cornerRadius(12)
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
        Section(header: sectionHeader("Project Details")) {
            TextField("Project name", text: $viewModel.name)
                .font(.custom("Inter-Regular", size: 16))
                .disabled(viewModel.isSaving)

            TextField(
                "Description (optional)",
                text: $viewModel.descriptionText,
                axis: .vertical
            )
            .font(.custom("Inter-Regular", size: 16))
            .lineLimit(3...6)
            .disabled(viewModel.isSaving)
        }
    }

    private var scheduleSection: some View {
        Section(header: sectionHeader("Schedule")) {
            Toggle("Include start date", isOn: $viewModel.includeStartDate)
                .font(.custom("Inter-Regular", size: 15))
                .disabled(viewModel.isSaving)
            if viewModel.includeStartDate {
                DatePicker("Start date", selection: $viewModel.startDate, displayedComponents: .date)
                    .font(.custom("Inter-Regular", size: 15))
                    .disabled(viewModel.isSaving)
            }

            Toggle("Include end date", isOn: $viewModel.includeEndDate)
                .font(.custom("Inter-Regular", size: 15))
                .disabled(viewModel.isSaving)
            if viewModel.includeEndDate {
                DatePicker("End date", selection: $viewModel.endDate, displayedComponents: .date)
                    .font(.custom("Inter-Regular", size: 15))
                    .disabled(viewModel.isSaving)
            }

            // Parity note — Web only SENDS a date field when it's filled, so an untoggled date
            // here leaves the column untouched on the server (rather than clearing it). This
            // is intentional Round 1.9 parity with Web, not a bug.
            Text("Untoggling a date leaves the saved value unchanged (matches web behavior).")
                .font(.custom("Inter-Regular", size: 11))
                .foregroundColor(Color.Brand.textSecondary)
        }
    }

    private var statusProgressSection: some View {
        Section(header: sectionHeader("Status & Progress")) {
            Picker("Status", selection: $viewModel.status) {
                Text("Planning").tag(Project.ProjectStatus.planning)
                Text("Active").tag(Project.ProjectStatus.active)
                Text("On Hold").tag(Project.ProjectStatus.onHold)
                Text("Completed").tag(Project.ProjectStatus.completed)
                Text("Archived").tag(Project.ProjectStatus.archived)
            }
            .font(.custom("Inter-Regular", size: 15))
            .disabled(viewModel.isSaving)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Progress")
                        .font(.custom("Inter-Regular", size: 15))
                    Spacer()
                    Text("\(viewModel.progress)%")
                        .font(.custom("Inter-SemiBold", size: 14))
                        .foregroundColor(Color.Brand.primary)
                }
                Slider(
                    value: Binding(
                        get: { Double(viewModel.progress) },
                        set: { viewModel.progress = Int($0.rounded()) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .tint(Color.Brand.primary)
                .disabled(viewModel.isSaving)
            }
            .padding(.vertical, 4)
        }
    }

    private var membersSection: some View {
        Section(header: membersSectionHeader) {
            if let message = viewModel.candidatesErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(Color.Brand.warning)
                    Text("Couldn't load members: \(message)")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundColor(Color.Brand.warning)
                        .lineLimit(3)
                }
            } else if viewModel.isLoadingCandidates {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading members…")
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundColor(Color.Brand.textSecondary)
                }
            } else if viewModel.candidates.isEmpty {
                Text("No active workspace members found.")
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundColor(Color.Brand.textSecondary)
            } else {
                TextField("Search members", text: $viewModel.memberSearch)
                    .font(.custom("Inter-Regular", size: 15))
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
            sectionHeader("Members")
            Spacer()
            Text("\(viewModel.selectedMemberIds.count) selected")
                .font(.custom("Inter-Regular", size: 11))
                .foregroundColor(Color.Brand.textSecondary)
                .textCase(nil)
        }
    }

    private func memberRow(candidate: ProjectMemberCandidate) -> some View {
        let isOwner = viewModel.ownerId == candidate.id
        let isSelected = viewModel.selectedMemberIds.contains(candidate.id)
        return Button {
            viewModel.toggleMember(candidate.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? Color.Brand.primary : Color.Brand.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(candidate.displayName)
                            .font(.custom("Inter-Medium", size: 14))
                            .foregroundColor(Color.Brand.text)
                            .lineLimit(1)
                        if isOwner {
                            Text("Owner")
                                .font(.custom("Inter-SemiBold", size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.Brand.primaryLight)
                                .foregroundColor(Color.Brand.primary)
                                .clipShape(Capsule())
                        }
                    }
                    if let secondary = secondaryLine(candidate: candidate) {
                        Text(secondary)
                            .font(.custom("Inter-Regular", size: 11))
                            .foregroundColor(Color.Brand.textSecondary)
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
            .font(.custom("Inter-Medium", size: 13))
            .foregroundColor(.gray)
    }

    private func submit() async {
        if let refreshed = await viewModel.save() {
            onSaved(refreshed)
            dismiss()
        }
        // If save failed, `errorMessage` is already set on the VM and rendered in the form.
    }
}
