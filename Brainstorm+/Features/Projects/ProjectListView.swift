import SwiftUI
import Combine
import Supabase

public struct ProjectListView: View {
    @StateObject private var viewModel: ProjectListViewModel

    /// Identity source for server-side membership scoping — mirrors `guard.role` /
    /// `guard.userId` in `BrainStorm+-Web/src/lib/actions/projects.ts`.
    @Environment(SessionManager.self) private var sessionManager

    /// 1.9: secondary edit entry on list rows. Holds the project whose edit sheet is
    /// currently being presented; `nil` hides the sheet. Using an identifiable binding
    /// (rather than a bool) so SwiftUI re-creates the sheet when a different row is edited
    /// in quick succession.
    @State private var projectBeingEdited: Project? = nil

    /// 2.0: row-level delete entry. Same identifiable-binding pattern as
    /// `projectBeingEdited` so rapid row-switching creates a fresh confirmation dialog
    /// targeting the correct project.
    @State private var projectPendingDelete: Project? = nil

    public init(viewModel: ProjectListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.Brand.background
                    .ignoresSafeArea()

                Group {
                    if viewModel.isLoading && viewModel.projects.isEmpty {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(Color.Brand.primary)
                    } else if let error = viewModel.errorMessage, viewModel.projects.isEmpty {
                        errorStateView(message: error)
                    } else if viewModel.scopeOutcome == .noMembership {
                        noMembershipStateView
                    } else if viewModel.projects.isEmpty {
                        if hasActiveFilter {
                            filteredEmptyStateView
                        } else {
                            emptyStateView
                        }
                    } else {
                        contentList
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    statusFilterMenu
                }
            }
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search projects"
            )
            .onSubmit(of: .search) {
                // User pressed the Search key on the keyboard — push the server-side `ilike`.
                Task { await reload() }
            }
            .onChange(of: viewModel.searchText) { _, newValue in
                // Handles the `.searchable` clear (X) affordance — when the user empties the
                // field we must re-fetch without the `ilike` filter so the list isn't frozen
                // at the last server-side filtered result set.
                if newValue.isEmpty {
                    Task { await reload() }
                }
            }
            .onChange(of: viewModel.statusFilter) { _, _ in
                // Discrete choice — safe to trigger server-side `eq('status', s)` immediately.
                Task { await reload() }
            }
            .refreshable {
                await reload()
            }
            .task {
                await reload()
            }
            // 1.9: secondary edit entry. Long-press on a row surfaces a context-menu "Edit"
            // action which sets `projectBeingEdited`, triggering this identifiable sheet.
            .sheet(item: $projectBeingEdited) { project in
                ProjectEditSheet(
                    client: supabase,
                    project: project,
                    onSaved: { _ in
                        Task { await reload() }
                    }
                )
            }
            // 2.0: row-level delete confirmation. Mirrors Web `confirm('确定删除这个项目吗？')`
            // semantics via the native `.confirmationDialog` + `Button(role: .destructive)`
            // pattern. The destructive action is gated behind `isDeleting` to prevent double-taps.
            .confirmationDialog(
                "Delete project?",
                isPresented: Binding(
                    get: { projectPendingDelete != nil },
                    set: { newValue in if !newValue { projectPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: projectPendingDelete
            ) { project in
                Button("Delete \"\(project.name)\"", role: .destructive) {
                    Task {
                        let succeeded = await viewModel.deleteProject(id: project.id)
                        projectPendingDelete = nil
                        if !succeeded {
                            // Error surfaces via the `.alert` below; list rows stay intact.
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    projectPendingDelete = nil
                }
            } message: { project in
                Text("This permanently deletes “\(project.name)” and all of its members. This cannot be undone.")
            }
            .alert(
                "Delete failed",
                isPresented: Binding(
                    get: { viewModel.deleteErrorMessage != nil },
                    set: { newValue in if !newValue { viewModel.deleteErrorMessage = nil } }
                ),
                actions: {
                    Button("OK", role: .cancel) { viewModel.deleteErrorMessage = nil }
                },
                message: {
                    Text(viewModel.deleteErrorMessage ?? "")
                }
            )
        }
    }

    // MARK: - Identity / reload

    private var primaryRole: PrimaryRole? {
        // SessionManager exposes the raw `profile.role` string; RBACManager is the single
        // normalization surface used across iOS for mapping legacy strings onto PrimaryRole.
        RBACManager.shared.migrateLegacyRole(sessionManager.currentProfile?.role).primaryRole
    }

    private var userId: UUID? {
        sessionManager.currentProfile?.id
    }

    private func reload() async {
        await viewModel.fetchProjects(role: primaryRole, userId: userId)
    }

    private var hasActiveFilter: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || viewModel.statusFilter != nil
    }

    // MARK: - Subviews

    private var contentList: some View {
        // Server is authoritative; `filteredProjects` is a thin client smoothing layer.
        let rows = viewModel.filteredProjects
        return Group {
            if rows.isEmpty {
                filteredEmptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(rows) { project in
                            NavigationLink {
                                ProjectDetailView(
                                    viewModel: ProjectDetailViewModel(
                                        client: supabase,
                                        initialProject: project
                                    ),
                                    // 1.9: when edit succeeds inside the pushed detail view,
                                    // reload the list so the updated row reflects the save.
                                    onProjectUpdated: { _ in
                                        Task { await reload() }
                                    },
                                    // 2.0: when delete succeeds inside the pushed detail view,
                                    // drop the row locally (no extra PostgREST round-trip — the
                                    // detail has already confirmed the server-side delete).
                                    onProjectDeleted: { id in
                                        viewModel.removeProjectLocally(id: id)
                                    }
                                )
                            } label: {
                                ProjectCardView(
                                    project: project,
                                    // 1.7: feed the batched owner lookup into the card so it can
                                    // show `full_name` when available (mirrors Web's nested
                                    // `profiles:owner_id(full_name, avatar_url)` join).
                                    owner: project.ownerId.flatMap { viewModel.ownersById[$0] },
                                    // 2.1: feed the batched task count aggregate into the card.
                                    // `nil` when the count isn't yet fetched or failed; card
                                    // hides the count label rather than showing a stale value.
                                    taskCount: viewModel.taskCountsByProject[project.id]
                                )
                                    .padding(.horizontal, 20)
                            }
                            .buttonStyle(.plain)
                            // 1.9: secondary edit entry. Long-press the row to surface the
                            // same edit sheet used from the detail toolbar.
                            // 2.0: secondary delete entry with destructive role + its own
                            // confirmation dialog (see `.confirmationDialog` above).
                            .contextMenu {
                                Button {
                                    projectBeingEdited = project
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    projectPendingDelete = project
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        Spacer().frame(height: 24)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var statusFilterMenu: some View {
        Menu {
            Button {
                viewModel.statusFilter = nil
            } label: {
                Label("All statuses", systemImage: viewModel.statusFilter == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(Self.statusOptions, id: \.0) { option in
                Button {
                    viewModel.statusFilter = option.0
                } label: {
                    Label(option.1, systemImage: viewModel.statusFilter == option.0 ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: viewModel.statusFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .foregroundColor(Color.Brand.primary)
        }
    }

    private static let statusOptions: [(Project.ProjectStatus, String)] = [
        (.planning, "Planning"),
        (.active, "Active"),
        (.onHold, "On Hold"),
        (.completed, "Completed"),
        (.archived, "Archived"),
    ]

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.Brand.accent.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "folder")
                    .font(.system(size: 40))
                    .foregroundColor(Color.Brand.primary)
            }
            Text("No projects yet")
                .font(.custom("Outfit-SemiBold", size: 20))
                .foregroundColor(Color.Brand.text)
            Text("Projects created on the web will appear here.")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundColor(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
        .padding(.horizontal, 24)
    }

    /// Rendered when the server returns no rows because the current user is a non-admin
    /// with zero `project_members` rows — mirrors Web's early-return empty path.
    private var noMembershipStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.Brand.accent.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "person.2.slash")
                    .font(.system(size: 36))
                    .foregroundColor(Color.Brand.primary)
            }
            Text("No accessible projects")
                .font(.custom("Outfit-SemiBold", size: 20))
                .foregroundColor(Color.Brand.text)
            Text("You aren't a member of any project yet. A workspace admin can add you from the Web dashboard.")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundColor(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 4)
        .padding(.horizontal, 24)
    }

    private var filteredEmptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(Color.Brand.textSecondary)
            Text("No matches")
                .font(.custom("Outfit-SemiBold", size: 18))
                .foregroundColor(Color.Brand.text)
            Text("Try a different search term or clear the status filter.")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundColor(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(Color.Brand.warning)
            Text("Couldn't load projects")
                .font(.custom("Outfit-SemiBold", size: 18))
                .foregroundColor(Color.Brand.text)
            Text(message)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundColor(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await reload() }
            } label: {
                Text("Retry")
                    .font(.custom("Inter-SemiBold", size: 14))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.Brand.primary)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 24)
    }
}
