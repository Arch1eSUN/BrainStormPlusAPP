import SwiftUI
import Combine

public struct ProjectDetailView: View {
    @StateObject private var viewModel: ProjectDetailViewModel

    /// Same identity source used by `ProjectListView` — `SessionManager.currentProfile` resolved
    /// through `RBACManager.migrateLegacyRole(...)`.
    @Environment(SessionManager.self) private var sessionManager

    /// 2.0: SwiftUI's pop helper. Used to dismiss the pushed detail view after a successful
    /// project delete so the user lands back on the list without seeing a flash of deleted
    /// state. The VM clears `project` before dismiss() runs to avoid any stale render.
    @Environment(\.dismiss) private var dismiss

    /// 1.9: optional callback fired AFTER a successful edit save. The presenting view (normally
    /// `ProjectListView`) uses this to re-run its list fetch so the updated row shows up
    /// without waiting for a manual pull-to-refresh. `nil` is fine — the detail view still
    /// refreshes itself via `fetchDetail(...)` on save regardless.
    private let onProjectUpdated: ((Project) -> Void)?

    /// 2.0: optional callback fired AFTER a successful project delete. The presenting view
    /// (normally `ProjectListView`) uses this to drop the deleted row locally without a
    /// round-trip. `nil` is fine — the server-side delete still happened.
    private let onProjectDeleted: ((UUID) -> Void)?

    /// 1.9: local presentation state for the edit sheet. Held at the detail-view level so the
    /// sheet is keyed to whatever project is currently being viewed.
    @State private var isShowingEditSheet: Bool = false

    /// 2.0: local presentation state for the delete confirmation dialog.
    @State private var isShowingDeleteConfirm: Bool = false

    /// 2.6: local presentation state for the "Convert to risk action" confirmation dialog.
    /// Held at the view level so the dialog's lifecycle is independent from the VM — the
    /// VM owns `riskActionSyncPhase`, but the confirm-before-insert step is pure View
    /// concern (the VM only transitions to `.syncing` once the user actually confirms).
    @State private var isShowingRiskActionSyncConfirm: Bool = false

    /// 2.6: the draft captured at the moment the user tapped "Convert to risk action". We
    /// snapshot the draft instead of recomputing it inside the dialog so a background
    /// `fetchDetail()` refresh can't mutate the preview between the tap and the confirm.
    /// The VM still rebuilds its own authoritative draft inside `syncRiskActionFromDetail`
    /// before the actual insert — this snapshot is purely for the dialog copy.
    @State private var pendingRiskActionDraft: RiskActionSyncDraft? = nil

    public init(
        viewModel: ProjectDetailViewModel,
        onProjectUpdated: ((Project) -> Void)? = nil,
        onProjectDeleted: ((UUID) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onProjectUpdated = onProjectUpdated
        self.onProjectDeleted = onProjectDeleted
    }

    public var body: some View {
        ZStack {
            Color.Brand.background
                .ignoresSafeArea()

            Group {
                if viewModel.accessOutcome == .denied {
                    deniedStateView
                } else if let project = viewModel.project {
                    detailScroll(project: project)
                } else if viewModel.isLoading {
                    ProgressView()
                        .tint(Color.Brand.primary)
                } else if let error = viewModel.errorMessage {
                    errorStateView(message: error)
                } else {
                    ProgressView()
                        .tint(Color.Brand.primary)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 1.9: edit entry. Only shown once the project row has resolved and access
            // didn't land on `.denied` — a denied caller must not see an edit affordance
            // for a project they can't read.
            if viewModel.accessOutcome != .denied, let _ = viewModel.project {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(Color.Brand.primary)
                    }
                    .accessibilityLabel("Edit project")
                    .disabled(viewModel.isDeleting)
                }
                // 2.0: delete entry. Same access gate as the edit button — a denied caller
                // must never see a destructive affordance for a project they can't read.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(Color.Brand.warning)
                    }
                    .accessibilityLabel("Delete project")
                    .disabled(viewModel.isDeleting)
                }
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading && viewModel.project != nil {
                ProgressView()
                    .tint(Color.Brand.primary)
                    .padding(.top, 8)
            }
        }
        // 2.0: dimmed progress overlay covers the scroll while a delete is in flight to
        // prevent accidental taps on child content. Matches the edit-sheet overlay pattern.
        .overlay {
            if viewModel.isDeleting {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView("Deleting…")
                    .tint(Color.Brand.primary)
                    .padding()
                    .background(Color.Brand.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            if let project = viewModel.project {
                ProjectEditSheet(
                    client: supabase,
                    project: project,
                    onSaved: { refreshed in
                        // Propagate to any parent list view so its row reflects the edit.
                        onProjectUpdated?(refreshed)
                        // And refresh this detail view so owner / enrichment / metadata all
                        // reflect the saved row + any membership changes.
                        Task { await reload() }
                    }
                )
            }
        }
        // 2.0: destructive confirmation. Mirrors Web `confirm('确定删除这个项目吗？')` intent
        // gate with an iOS-native `.confirmationDialog` + `Button(role: .destructive)`.
        .confirmationDialog(
            "Delete project?",
            isPresented: $isShowingDeleteConfirm,
            titleVisibility: .visible
        ) {
            if let project = viewModel.project {
                Button("Delete \"\(project.name)\"", role: .destructive) {
                    Task { await confirmDelete() }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let project = viewModel.project {
                Text("This permanently deletes “\(project.name)” and all of its members. This cannot be undone.")
            } else {
                Text("This permanently deletes this project. This cannot be undone.")
            }
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
        .refreshable {
            await reload()
        }
        .task {
            await reload()
        }
    }

    // MARK: - Identity / reload

    private var primaryRole: PrimaryRole? {
        RBACManager.shared.migrateLegacyRole(sessionManager.currentProfile?.role).primaryRole
    }

    private var userId: UUID? {
        sessionManager.currentProfile?.id
    }

    /// 2.6: raw role string straight from the session profile. Distinct from `primaryRole`
    /// because `RBACManager.canManageRiskActions(rawRole:)` gates against Web's exact
    /// role set (`['super_admin', 'superadmin', 'admin', 'hr_admin', 'manager']`), and
    /// iOS's `RBACManager.migrateLegacyRole(_:)` drops `hr_admin` and folds legacy
    /// `chairperson` / `super_admin` into `.superadmin`. Using the raw string here keeps
    /// the client gate in lockstep with server-side RLS (migrations 014 + 037).
    private var rawRole: String? {
        sessionManager.currentProfile?.role
    }

    private var canSyncRiskAction: Bool {
        RBACManager.shared.canManageRiskActions(rawRole: rawRole)
    }

    private func reload() async {
        await viewModel.fetchDetail(role: primaryRole, userId: userId)
    }

    /// 2.0: drives the delete. On success we notify the presenting list (so it can drop the
    /// row without a re-fetch) and pop the detail view. The VM has already cleared `project`
    /// by the time we dismiss, so the pop animation won't flash deleted-row data.
    private func confirmDelete() async {
        let projectId = viewModel.projectId
        let succeeded = await viewModel.deleteProject()
        if succeeded {
            onProjectDeleted?(projectId)
            dismiss()
        }
        // Failure surfaces via `viewModel.deleteErrorMessage` → `.alert(...)`. Detail view
        // stays open so the user can retry.
    }

    private var navigationTitle: String {
        if viewModel.accessOutcome == .denied { return "Project" }
        return viewModel.project?.name ?? "Project"
    }

    // MARK: - Detail layout

    private func detailScroll(project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(project: project)
                metadataSection(project: project)
                progressSection(project: project)

                if let description = project.description, !description.isEmpty {
                    descriptionSection(description: description)
                }

                // 1.7 read-only enrichment sections.
                tasksSection
                dailyLogsSection
                weeklySummariesSection

                // 2.2: AI summary foundation. Sits after the read-only enrichment sections so
                // users can scan tasks / daily logs / weekly reports first, then trigger the
                // summary synthesis on demand. Failure is isolated via `summaryErrorMessage`
                // and does not affect anything above.
                aiSummarySection

                // 2.3: Risk analysis foundation (read-only). Surfaces the most recent
                // `project_risk_summaries` row generated by the web dashboard. Failure is
                // isolated via `riskAnalysisErrorMessage` and does not affect the summary
                // section, enrichment sections, or detail row.
                riskAnalysisSection

                // 2.4: Linked risk actions foundation (read-only). Sits directly below the
                // risk analysis section because its data model (`risk_actions.ai_source_id
                // = project_risk_summaries.id`) is anchored to that analysis. Failure is
                // isolated via `linkedRiskActionsErrorMessage` and does not affect the
                // risk analysis section, summary section, enrichment sections, or detail row.
                linkedRiskActionsSection

                // 2.5: Resolution feedback foundation (read-only). Aggregated over the same
                // `risk_actions` table the 2.4 section pulls from, anchored to the same
                // `project_risk_summaries.id`. Provides governance badges + counts + top-3
                // recent resolutions. Failure is isolated via
                // `resolutionFeedbackErrorMessage` and does not affect any section above.
                resolutionFeedbackSection

                if let error = viewModel.errorMessage {
                    errorBanner(message: error)
                }

                foundationScopeNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Sections

    private func headerSection(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(project.name)
                .font(.custom("Outfit-Bold", size: 26))
                .foregroundColor(Color.Brand.text)

            statusBadge(status: project.status)
        }
    }

    private func statusBadge(status: Project.ProjectStatus) -> some View {
        let (label, fg, bg) = Self.statusStyle(for: status)
        return Text(label)
            .font(.custom("Inter-SemiBold", size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(bg)
            .foregroundColor(fg)
            .clipShape(Capsule())
    }

    private func metadataSection(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let start = project.startDate {
                metaRow(icon: "calendar", label: "Start", value: Self.dateFormatter.string(from: start))
            }
            if let end = project.endDate {
                metaRow(icon: "calendar.badge.clock", label: "End", value: Self.dateFormatter.string(from: end))
            }
            // 1.7: owner row now prefers the joined profile's full_name. If owner fetch failed
            // (recorded in `enrichmentErrors[.owner]`) we fall back to the raw UUID rather than
            // hiding the row, so the detail still shows *something* for the owner field.
            ownerMetaRow(project: project)
            if let createdAt = project.createdAt {
                metaRow(icon: "clock", label: "Created", value: Self.dateFormatter.string(from: createdAt))
            }
        }
        .padding(16)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    @ViewBuilder
    private func ownerMetaRow(project: Project) -> some View {
        // 1.8: when we have an `avatar_url`, render a real avatar circle in place of the icon.
        // Falls through to the SF-symbol icon when avatar is missing / invalid / fails to load.
        let avatarUrl = viewModel.owner?.avatarUrl
        let ownerFullName = viewModel.owner?.fullName

        if let ownerFullName, !ownerFullName.isEmpty {
            ownerMetaRowLayout(label: "Owner", value: ownerFullName, avatarUrl: avatarUrl)
        } else if let ownerId = project.ownerId {
            // Either owner hasn't loaded yet, profile has no full_name, or the owner fetch
            // recorded an error. Keep the UUID visible so the field isn't silently empty.
            ownerMetaRowLayout(label: "Owner", value: ownerId.uuidString, avatarUrl: avatarUrl)
        }
    }

    /// Owner-row layout: inline avatar (or person icon fallback) + label + value. Mirrors the
    /// shape of `metaRow` so the metadata card stays visually consistent.
    private func ownerMetaRowLayout(label: String, value: String, avatarUrl: String?) -> some View {
        HStack(spacing: 12) {
            ownerAvatarView(urlString: avatarUrl, diameter: 22)
            Text(label)
                .font(.custom("Inter-Medium", size: 13))
                .foregroundColor(Color.Brand.textSecondary)
            Spacer()
            Text(value)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundColor(Color.Brand.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// SwiftUI-native `AsyncImage` with robust fallbacks:
    /// 1. nil / empty / invalid URL → SF `person.crop.circle.fill` placeholder
    /// 2. load failure → same placeholder (avatar failure MUST NOT leak into `errorMessage`)
    /// 3. in-flight → placeholder (no spinner — foundation look)
    @ViewBuilder
    private func ownerAvatarView(urlString: String?, diameter: CGFloat) -> some View {
        if let s = urlString, !s.isEmpty, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    ownerAvatarPlaceholder
                @unknown default:
                    ownerAvatarPlaceholder
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.Brand.primaryLight.opacity(0.4), lineWidth: 0.5))
        } else {
            ownerAvatarPlaceholder
                .frame(width: diameter, height: diameter)
        }
    }

    private var ownerAvatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(Color.Brand.primary.opacity(0.75))
    }

    private func metaRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color.Brand.primary)
                .frame(width: 20)
            Text(label)
                .font(.custom("Inter-Medium", size: 13))
                .foregroundColor(Color.Brand.textSecondary)
            Spacer()
            Text(value)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundColor(Color.Brand.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func progressSection(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Progress")
                    .font(.custom("Outfit-SemiBold", size: 16))
                    .foregroundColor(Color.Brand.text)
                Spacer()
                Text("\(project.progress)%")
                    .font(.custom("Inter-SemiBold", size: 14))
                    .foregroundColor(Color.Brand.primary)
            }
            ProgressView(value: Double(min(max(project.progress, 0), 100)) / 100.0)
                .progressViewStyle(.linear)
                .tint(Color.Brand.primary)
        }
        .padding(16)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    private func descriptionSection(description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Description")
                .font(.custom("Outfit-SemiBold", size: 16))
                .foregroundColor(Color.Brand.text)
            Text(description)
                .font(.custom("Inter-Regular", size: 14))
                .foregroundColor(Color.Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - 1.7 read-only enrichment sections

    /// Compact list of up to 50 tasks attached to this project (Web parity: `fetchProjectDetail()`
    /// `tasks` sub-select). Read-only; no navigation, no edit — that belongs to the Tasks module.
    private var tasksSection: some View {
        enrichmentCard(
            title: "Tasks",
            subtitle: tasksSubtitle,
            errorMessage: viewModel.enrichmentErrors[.tasks]
        ) {
            if viewModel.tasks.isEmpty && viewModel.enrichmentErrors[.tasks] == nil {
                emptyLine("No tasks for this project yet.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.tasks.prefix(8)) { task in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle")
                                .foregroundColor(Self.taskStatusColor(task.status))
                                .frame(width: 16)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.custom("Inter-Medium", size: 13))
                                    .foregroundColor(Color.Brand.text)
                                    .lineLimit(2)
                                Text(taskMetaLine(for: task))
                                    .font(.custom("Inter-Regular", size: 11))
                                    .foregroundColor(Color.Brand.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if viewModel.tasks.count > 8 {
                        Text("+ \(viewModel.tasks.count - 8) more")
                            .font(.custom("Inter-Medium", size: 11))
                            .foregroundColor(Color.Brand.textSecondary)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var tasksSubtitle: String? {
        guard viewModel.enrichmentErrors[.tasks] == nil else { return nil }
        return viewModel.tasks.isEmpty ? nil : "\(viewModel.tasks.count) shown"
    }

    /// Compact list of up to 10 recent daily logs (Web parity: `fetchProjectDetail()`
    /// `recent_daily_logs` sub-select).
    private var dailyLogsSection: some View {
        enrichmentCard(
            title: "Recent Daily Logs",
            subtitle: dailyLogsSubtitle,
            errorMessage: viewModel.enrichmentErrors[.dailyLogs]
        ) {
            if viewModel.dailyLogs.isEmpty && viewModel.enrichmentErrors[.dailyLogs] == nil {
                emptyLine("No daily logs yet for this project.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.dailyLogs.prefix(5)) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(log.date)
                                    .font(.custom("Inter-SemiBold", size: 12))
                                    .foregroundColor(Color.Brand.primary)
                                if let authorLine = authorLine(forUserId: log.userId) {
                                    Text("·")
                                        .font(.custom("Inter-Regular", size: 11))
                                        .foregroundColor(Color.Brand.textSecondary)
                                    Text(authorLine)
                                        .font(.custom("Inter-Medium", size: 11))
                                        .foregroundColor(Color.Brand.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Text(log.content)
                                .font(.custom("Inter-Regular", size: 13))
                                .foregroundColor(Color.Brand.text)
                                .lineLimit(3)
                            if let blockers = log.blockers, !blockers.isEmpty {
                                Text("Blockers: \(blockers)")
                                    .font(.custom("Inter-Regular", size: 11))
                                    .foregroundColor(Color.Brand.warning)
                                    .lineLimit(2)
                            }
                        }
                    }
                    if viewModel.dailyLogs.count > 5 {
                        Text("+ \(viewModel.dailyLogs.count - 5) more")
                            .font(.custom("Inter-Medium", size: 11))
                            .foregroundColor(Color.Brand.textSecondary)
                    }
                }
            }
        }
    }

    private var dailyLogsSubtitle: String? {
        guard viewModel.enrichmentErrors[.dailyLogs] == nil else { return nil }
        return viewModel.dailyLogs.isEmpty ? nil : "\(viewModel.dailyLogs.count) recent"
    }

    /// Compact list of up to 5 recent weekly summaries (Web parity: `fetchProjectDetail()`
    /// `weekly_summaries` sub-select where `project_ids @> [projectId]`).
    private var weeklySummariesSection: some View {
        enrichmentCard(
            title: "Weekly Summaries",
            subtitle: weeklySubtitle,
            errorMessage: viewModel.enrichmentErrors[.weeklySummaries]
        ) {
            if viewModel.weeklySummaries.isEmpty && viewModel.enrichmentErrors[.weeklySummaries] == nil {
                emptyLine("No weekly summaries yet for this project.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.weeklySummaries.prefix(3)) { week in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Week of \(week.weekStart)")
                                    .font(.custom("Inter-SemiBold", size: 12))
                                    .foregroundColor(Color.Brand.primary)
                                if let authorLine = authorLine(forUserId: week.userId) {
                                    Text("·")
                                        .font(.custom("Inter-Regular", size: 11))
                                        .foregroundColor(Color.Brand.textSecondary)
                                    Text(authorLine)
                                        .font(.custom("Inter-Medium", size: 11))
                                        .foregroundColor(Color.Brand.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Text(week.summary)
                                .font(.custom("Inter-Regular", size: 13))
                                .foregroundColor(Color.Brand.text)
                                .lineLimit(3)
                            if let highlights = week.highlights, !highlights.isEmpty {
                                Text("Highlights: \(highlights)")
                                    .font(.custom("Inter-Regular", size: 11))
                                    .foregroundColor(Color.Brand.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    if viewModel.weeklySummaries.count > 3 {
                        Text("+ \(viewModel.weeklySummaries.count - 3) more")
                            .font(.custom("Inter-Medium", size: 11))
                            .foregroundColor(Color.Brand.textSecondary)
                    }
                }
            }
        }
    }

    private var weeklySubtitle: String? {
        guard viewModel.enrichmentErrors[.weeklySummaries] == nil else { return nil }
        return viewModel.weeklySummaries.isEmpty ? nil : "\(viewModel.weeklySummaries.count) shown"
    }

    @ViewBuilder
    private func enrichmentCard<Content: View>(
        title: String,
        subtitle: String?,
        errorMessage: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.custom("Outfit-SemiBold", size: 16))
                    .foregroundColor(Color.Brand.text)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.custom("Inter-Medium", size: 11))
                        .foregroundColor(Color.Brand.textSecondary)
                }
            }
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(Color.Brand.warning)
                    Text("Couldn't load: \(errorMessage)")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundColor(Color.Brand.warning)
                        .lineLimit(3)
                }
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.custom("Inter-Regular", size: 12))
            .foregroundColor(Color.Brand.textSecondary)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(Color.Brand.warning)
            Text(message)
                .font(.custom("Inter-Medium", size: 13))
                .foregroundColor(Color.Brand.warning)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.Brand.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 1.8 sublist display helpers

    /// Meta line for a task row: `Status · Priority` baseline plus ` · Assignee` when the 1.8
    /// sublist profile hydrate (or the already-hydrated owner) can resolve the id. When the
    /// assignee id exists but we can't resolve a name (hydrate not ready / failed / profile has
    /// no `full_name`), we intentionally omit the assignee token rather than showing a UUID in
    /// the secondary line — keeps the compact look clean.
    private func taskMetaLine(for task: ProjectTaskSummary) -> String {
        let base = "\(Self.humanize(task.status)) · \(Self.humanize(task.priority))"
        if let name = viewModel.displayName(forUserId: task.assigneeId) {
            return "\(base) · \(name)"
        }
        return base
    }

    /// Author sub-line for daily logs / weekly summaries. Returns `"By <name>"` when the batched
    /// hydrate resolved a full_name, or `nil` when it didn't — callers can then drop the byline
    /// element instead of rendering "By <uuid>".
    private func authorLine(forUserId userId: UUID?) -> String? {
        guard let name = viewModel.displayName(forUserId: userId) else { return nil }
        return "By \(name)"
    }

    private var foundationScopeNote: some View {
        // 2.6: the "convert risk analysis to risk action" write path landed this round for
        // admin / manager roles. Still deferred on iOS: resolution write-backs (close /
        // reopen / effectiveness / governance note), generating fresh risk analyses from
        // iOS, and the full risk action management surface.
        Text("Generating fresh risk analyses and writing resolution outcomes (close / reopen / effectiveness) remain on the web and will arrive in later iOS rounds.")
            .font(.custom("Inter-Regular", size: 12))
            .foregroundColor(Color.Brand.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.Brand.primaryLight.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 2.2 AI summary foundation section

    /// Detail-page entry for the 2.2 AI summary foundation. State machine:
    /// - idle (no `summary`, no `summaryErrorMessage`, not `isGeneratingSummary`):
    ///     shows a single "Generate summary" button.
    /// - generating: shows an in-place `ProgressView` + disabled button.
    /// - success: shows the synthesized summary text + a "Regenerate" button.
    /// - error: shows an isolated warning row + "Try again" button (plus any previously
    ///     synthesized summary, if one was kept — foundation keeps it conservative: we clear
    ///     `summary` on the failure path, so only the warning renders).
    ///
    /// Web parity note: Web's `generateProjectSummary(projectId)` is a server action, not an
    /// HTTP endpoint; iOS therefore synthesizes a deterministic facts summary from the same
    /// parallel Supabase fetch Web uses (30 tasks / 10 daily logs / 3 weekly reports). The
    /// foundation label makes this honest; an LLM-backed realignment is a later round.
    private var aiSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Project Summary")
                    .font(.custom("Outfit-SemiBold", size: 16))
                    .foregroundColor(Color.Brand.text)
                Spacer()
                if let generatedAt = viewModel.summary?.generatedAt {
                    Text("Generated \(Self.generatedAtFormatter.string(from: generatedAt))")
                        .font(.custom("Inter-Medium", size: 11))
                        .foregroundColor(Color.Brand.textSecondary)
                }
            }

            Text("Foundation snapshot · synthesized locally from tasks, daily logs, and weekly reports. AI-generated narrative arrives in a later iOS round.")
                .font(.custom("Inter-Regular", size: 11))
                .foregroundColor(Color.Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = viewModel.summaryErrorMessage {
                summaryErrorRow(message: errorMessage)
            } else if let summary = viewModel.summary {
                Text(summary.summary)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundColor(Color.Brand.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            summaryActionButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    @ViewBuilder
    private var summaryActionButton: some View {
        let hasResult = viewModel.summary != nil
        let hasError = viewModel.summaryErrorMessage != nil
        let label: String = {
            if viewModel.isGeneratingSummary { return "Generating…" }
            if hasError { return "Try again" }
            if hasResult { return "Regenerate summary" }
            return "Generate summary"
        }()

        HStack {
            Spacer()
            Button {
                Task { await viewModel.generateSummary() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isGeneratingSummary {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(label)
                        .font(.custom("Inter-SemiBold", size: 13))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.Brand.primary)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            // Prevent double-tap while generating AND lock out while a delete is in flight
            // so the two mutating-ish actions can't race. Summary doesn't mutate the row but
            // it issues three parallel reads — sharing the `isDeleting` guard is a safe
            // belt-and-braces measure and mirrors the same guard on the edit button.
            .disabled(viewModel.isGeneratingSummary || viewModel.isDeleting)
        }
    }

    private func summaryErrorRow(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(Color.Brand.warning)
            Text(message)
                .font(.custom("Inter-Regular", size: 12))
                .foregroundColor(Color.Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.Brand.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static let generatedAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - 2.3 Risk Analysis foundation section

    /// Detail-page entry for the 2.3 Risk Analysis foundation. State machine:
    /// - idle (no `riskAnalysis`, no `riskAnalysisErrorMessage`, not loading, haven't looked yet):
    ///     shows a single "Check for risk analysis" button + subtitle explaining read-only posture.
    /// - loading: button flips to "Checking…" with inline `ProgressView`, disabled.
    /// - success (cached row resolved): risk-level badge in header, summary text, provenance caption
    ///     ("Generated <time> · <model>"), button flips to "Refresh".
    /// - empty (looked, nothing cached): honest hint "No risk analysis has been generated on the
    ///     web yet…" — distinguishes from the idle state via `riskAnalysisNotYetGenerated`.
    /// - error: isolated warning row, button flips to "Try again"; any previously-resolved snapshot
    ///     stays visible underneath so a flaky network call doesn't wipe valid context.
    ///
    /// Web parity note: Web's `generateProjectRiskAnalysis(projectId)` is a server action with no
    /// HTTP exposure, so iOS cannot trigger a fresh analysis. iOS 2.3 is purely read-only —
    /// it reads the persisted row from `project_risk_summaries` that the web dashboard wrote on
    /// its most recent regenerate. A future round that lands `/api/ai/project-risk` (or a
    /// Supabase Edge Function proxying `askAI`) can drop in a generate action alongside
    /// `refreshRiskAnalysis()` without changing the UI binding.
    private var riskAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Risk Analysis")
                    .font(.custom("Outfit-SemiBold", size: 16))
                    .foregroundColor(Color.Brand.text)
                Spacer()
                if let analysis = viewModel.riskAnalysis {
                    riskLevelBadge(level: analysis.riskLevel)
                }
            }

            Text("Read-only snapshot · loaded from the web dashboard's most recent analysis. New analyses must be generated on the web.")
                .font(.custom("Inter-Regular", size: 11))
                .foregroundColor(Color.Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = viewModel.riskAnalysisErrorMessage {
                summaryErrorRow(message: errorMessage)
            } else if let analysis = viewModel.riskAnalysis {
                VStack(alignment: .leading, spacing: 6) {
                    Text(analysis.summary)
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundColor(Color.Brand.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption = riskAnalysisProvenanceCaption(for: analysis) {
                        Text(caption)
                            .font(.custom("Inter-Medium", size: 11))
                            .foregroundColor(Color.Brand.textSecondary)
                    }
                }
            } else if viewModel.riskAnalysisNotYetGenerated {
                Text("No risk analysis has been generated on the web yet for this project.")
                    .font(.custom("Inter-Regular", size: 12))
                    .foregroundColor(Color.Brand.textSecondary)
            }

            riskAnalysisActionButton

            // 2.6: risk-action sync affordance. Sits inside the risk analysis card so the
            // write path is visually anchored to the analysis it converts (mirrors Web's
            // "转为风险动作" button placement at projects/page.tsx:685). Rendered only when
            // a risk analysis is resolved — otherwise there is nothing to convert.
            if viewModel.riskAnalysis != nil {
                riskActionSyncAffordance
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .confirmationDialog(
            "Convert risk analysis to risk action?",
            isPresented: $isShowingRiskActionSyncConfirm,
            titleVisibility: .visible,
            presenting: pendingRiskActionDraft
        ) { draft in
            Button("Create risk action") {
                Task {
                    // VM owns the authoritative draft rebuild + insert. On success the
                    // view schedules the 3s auto-clear; on failure the scoped error
                    // surfaces below the button and the phase reverts to .idle.
                    let ok = await viewModel.syncRiskActionFromDetail(rawRole: rawRole)
                    pendingRiskActionDraft = nil
                    if ok {
                        scheduleRiskActionSyncSuccessClear()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingRiskActionDraft = nil
            }
        } message: { draft in
            // Dialog preview mirrors the three user-visible inputs Web sends into
            // syncRiskFromDetection: title, trimmed detail, severity. A new risk_actions
            // row will be created with status 'open' and linked to the current analysis.
            Text("""
            A new risk action will be created and linked to this project's risk analysis.

            • Title: \(draft.title)
            • Severity: \(Self.riskActionSeverityLabel(draft.severity))
            • Detail: \(draft.detail.isEmpty ? "—" : draft.detail)
            """)
        }
    }

    // MARK: - 2.6 Risk action sync affordance

    /// The button row + scoped error / success hint inside `riskAnalysisSection`. Kept
    /// separate from `riskAnalysisActionButton` so the two concerns stay visually legible:
    /// the refresh button is a READ affordance (top-level risk analysis state), the sync
    /// button is a WRITE affordance gated by RBAC.
    @ViewBuilder
    private var riskActionSyncAffordance: some View {
        let isSyncing = viewModel.riskActionSyncPhase == .syncing
        let didSucceed = viewModel.riskActionSyncPhase == .succeeded

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button {
                    // Snapshot the draft at tap-time so a concurrent `fetchDetail()` can't
                    // mutate the preview between the tap and the confirmation.
                    guard let draft = viewModel.riskActionSyncDraft() else { return }
                    pendingRiskActionDraft = draft
                    isShowingRiskActionSyncConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        if isSyncing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.triangle.branch")
                        }
                        Text(isSyncing ? "Converting…" : "Convert to risk action")
                            .font(.custom("Inter-SemiBold", size: 13))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(canSyncRiskAction ? Color.Brand.warning : Color.Brand.textSecondary.opacity(0.4))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                // Disabled while: no privilege, mid-insert, a delete is in flight (to keep
                // destructive + write from racing), or the view model hasn't resolved a
                // draft yet (no analysis → no button rendered at all, guarded above).
                .disabled(!canSyncRiskAction || isSyncing || viewModel.isDeleting)
            }

            if !canSyncRiskAction {
                // Honest hint so a non-manager caller understands why the button is gray.
                // Do not hide the button: parity with Web, which always renders the
                // control and only surfaces the gate on the server side — but unlike Web,
                // iOS pre-gates so the user isn't surprised by an RLS error. The hint
                // keeps that predictability explicit.
                Text("Converting a risk into a risk action requires admin or manager privileges.")
                    .font(.custom("Inter-Regular", size: 11))
                    .foregroundColor(Color.Brand.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let errorMessage = viewModel.riskActionSyncErrorMessage {
                summaryErrorRow(message: errorMessage)
            }

            if didSucceed {
                // Success hint. Auto-clears after 3s via `scheduleRiskActionSyncSuccessClear`.
                // Mirrors Web's `✅ 已转为风险动作（已建立 AI 链路）` copy at
                // `projects/page.tsx:216` in spirit — iOS ships English-only copy this round.
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.Brand.primary)
                    Text("Risk action created and linked to this analysis.")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundColor(Color.Brand.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.Brand.primaryLight.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    /// Schedules a 3-second delay after a successful sync, then asks the VM to clear the
    /// `.succeeded` phase back to `.idle`. Mirrors Web's
    /// `setTimeout(() => setSyncMsg(null), 3000)` at projects/page.tsx:221. The VM guards
    /// against clearing a newer in-flight sync, so a rapid retry never loses its hint.
    private func scheduleRiskActionSyncSuccessClear() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            viewModel.clearRiskActionSyncSuccess()
        }
    }

    /// Maps the three-value `severity` vocabulary into a user-facing label for the
    /// confirmation dialog. The VM stores severity as a raw string to match the Web insert
    /// payload verbatim; rendering happens here.
    private static func riskActionSeverityLabel(_ severity: String) -> String {
        switch severity {
        case "high": return "High"
        case "medium": return "Medium"
        case "low": return "Low"
        default: return severity.capitalized
        }
    }

    @ViewBuilder
    private var riskAnalysisActionButton: some View {
        let hasResult = viewModel.riskAnalysis != nil
        let hasError = viewModel.riskAnalysisErrorMessage != nil
        let label: String = {
            if viewModel.isLoadingRiskAnalysis { return "Checking…" }
            if hasError { return "Try again" }
            if hasResult { return "Refresh" }
            return "Check for risk analysis"
        }()

        HStack {
            Spacer()
            Button {
                Task { await viewModel.refreshRiskAnalysis() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoadingRiskAnalysis {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "shield.checkered")
                    }
                    Text(label)
                        .font(.custom("Inter-SemiBold", size: 13))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.Brand.primary)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            // Prevent double-tap while fetching and lock out while a delete is in flight so
            // destructive + read can't race. Mirrors the 2.2 summary button disable rule.
            .disabled(viewModel.isLoadingRiskAnalysis || viewModel.isDeleting)
        }
    }

    private func riskLevelBadge(level: ProjectRiskAnalysis.RiskLevel) -> some View {
        let (label, fg, bg) = Self.riskLevelStyle(for: level)
        return Text(label)
            .font(.custom("Inter-SemiBold", size: 11))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bg)
            .foregroundColor(fg)
            .clipShape(Capsule())
    }

    private func riskAnalysisProvenanceCaption(for analysis: ProjectRiskAnalysis) -> String? {
        var parts: [String] = []
        if let generatedAt = analysis.generatedAt {
            parts.append("Generated " + Self.generatedAtFormatter.string(from: generatedAt))
        }
        if let model = analysis.model, !model.isEmpty {
            parts.append(model)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Risk-level palette. Stays within existing brand tokens for low/medium/high; uses
    /// SwiftUI's built-in `.red` for critical because there's no dedicated danger token in
    /// `Color.Brand`. Unknown values (e.g. Web wrote an unrecognized level) render neutrally
    /// rather than pretending to be "low".
    private static func riskLevelStyle(for level: ProjectRiskAnalysis.RiskLevel) -> (String, Color, Color) {
        switch level {
        case .low:
            return ("Low risk", Color.Brand.primary, Color.Brand.primaryLight)
        case .medium:
            return ("Medium risk", Color.Brand.warning, Color.Brand.warning.opacity(0.18))
        case .high:
            return ("High risk", .white, Color.Brand.warning)
        case .critical:
            return ("Critical risk", .white, Color.red)
        case .unknown:
            return ("Unknown", Color.Brand.textSecondary, Color.gray.opacity(0.15))
        }
    }

    // MARK: - Access-denied / error states

    /// Rendered when `fetchDetail(...)` resolved as `.denied` — mirrors Web's `'无权访问此项目'`
    /// early return. Intentionally hides every field of the tapped row so a non-member cannot
    /// continue reading seeded data that leaked from the list. 1.7 note: enrichment state is
    /// also cleared on the denied path (see `ProjectDetailViewModel.applyDeniedState()`), so
    /// owner / tasks / daily logs / weekly summaries are never rendered for a denied caller.
    private var deniedStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.Brand.warning.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "lock.shield")
                    .font(.system(size: 36))
                    .foregroundColor(Color.Brand.warning)
            }
            Text("Access restricted")
                .font(.custom("Outfit-SemiBold", size: 20))
                .foregroundColor(Color.Brand.text)
            Text("You don't have permission to view this project. A workspace admin can add you as a member from the web dashboard.")
                .font(.custom("Inter-Regular", size: 14))
                .foregroundColor(Color.Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        .padding(.horizontal, 24)
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(Color.Brand.warning)
            Text("Couldn't load project")
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

    // MARK: - Styling helpers

    private static func statusStyle(for status: Project.ProjectStatus) -> (String, Color, Color) {
        switch status {
        case .planning:
            return ("Planning", Color.Brand.primary, Color.Brand.primaryLight)
        case .active:
            return ("Active", .white, Color.Brand.primary)
        case .onHold:
            return ("On Hold", Color.Brand.warning, Color.Brand.warning.opacity(0.15))
        case .completed:
            return ("Completed", Color.Brand.textSecondary, Color.gray.opacity(0.15))
        case .archived:
            return ("Archived", Color.Brand.textSecondary, Color.gray.opacity(0.10))
        }
    }

    /// Loose mapping from the server's `tasks.status` string to a colour dot. Stays tolerant
    /// of unknown status values (the DTO decodes `status` as a raw `String`).
    private static func taskStatusColor(_ status: String) -> Color {
        switch status {
        case "done": return Color.Brand.primary
        case "in_progress", "review": return Color.Brand.warning
        default: return Color.Brand.textSecondary
        }
    }

    private static func humanize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - 2.4 Linked Risk Actions foundation section

    /// Detail-page entry for the 2.4 Linked Risk Actions foundation. Anchored to the risk
    /// analysis via `risk_actions.ai_source_id = project_risk_summaries.id`, so the section
    /// has its own "no source yet" state distinct from "source exists, zero linked actions".
    ///
    /// State machine (devprompt §3.C):
    /// - `.idle` (nothing checked yet, no error): "Check for linked actions" button + subtitle.
    /// - `.loading`: button flips to "Checking…" with inline `ProgressView`, disabled.
    /// - `.noRiskAnalysisSource`: honest hint "No risk analysis exists for this project yet.
    ///     Run one from the web dashboard first." — distinguishes from `.empty` so the user
    ///     knows whether to act on Web or wait.
    /// - `.empty`: honest hint "No risk actions have been linked to this analysis yet."
    /// - `.loaded`: compact list of up to 3 rows + "+ N more" hint (matches Web's slice(0, 3)),
    ///     status dot + title + severity capsule per row.
    /// - Failure: scoped warning row; any previously-resolved snapshot stays visible below
    ///     so a flaky network call doesn't wipe valid context.
    /// - Denied: handled by `applyDeniedState()` which resets the phase to `.idle`; the
    ///     detail view itself is already hidden behind `deniedStateView`.
    ///
    /// Web parity note: Web's `getLinkedRiskActions(projectId)` is a server action, not an
    /// HTTP route, but `risk_actions` is directly readable via PostgREST under the
    /// org-scoped SELECT policy. iOS runs the same two-step read (anchor lookup + filtered
    /// select) the server action runs. Writing new risk actions ("转为风险动作") remains
    /// Web-only and is explicitly out of scope.
    private var linkedRiskActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Linked Risk Actions")
                    .font(.custom("Outfit-SemiBold", size: 16))
                    .foregroundColor(Color.Brand.text)
                Spacer()
                if viewModel.linkedRiskActionsPhase == .loaded,
                   !viewModel.linkedRiskActions.isEmpty {
                    Text("\(viewModel.linkedRiskActions.count) linked")
                        .font(.custom("Inter-Medium", size: 11))
                        .foregroundColor(Color.Brand.textSecondary)
                }
            }

            Text("Linked to the current risk analysis. Convert a new risk action above; resolution write-backs (close / reopen / effectiveness) remain on the web for now.")
                .font(.custom("Inter-Regular", size: 11))
                .foregroundColor(Color.Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = viewModel.linkedRiskActionsErrorMessage {
                summaryErrorRow(message: errorMessage)
            }

            linkedRiskActionsBody

            linkedRiskActionsActionButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    @ViewBuilder
    private var linkedRiskActionsBody: some View {
        switch viewModel.linkedRiskActionsPhase {
        case .idle, .loading:
            // Nothing extra in the body — the action button at the bottom carries the
            // current state. An explicit loading message would be visually redundant
            // with the button's "Checking…" copy + spinner.
            EmptyView()

        case .noRiskAnalysisSource:
            Text("No risk analysis exists for this project yet. Run one from the web dashboard first, then come back to view its linked actions here.")
                .font(.custom("Inter-Regular", size: 12))
                .foregroundColor(Color.Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

        case .empty:
            Text("No risk actions have been linked to this analysis yet.")
                .font(.custom("Inter-Regular", size: 12))
                .foregroundColor(Color.Brand.textSecondary)

        case .loaded:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.linkedRiskActions.prefix(3)) { action in
                    linkedRiskActionRow(action: action)
                }
                if viewModel.linkedRiskActions.count > 3 {
                    Text("+ \(viewModel.linkedRiskActions.count - 3) more on the web dashboard")
                        .font(.custom("Inter-Medium", size: 11))
                        .foregroundColor(Color.Brand.textSecondary)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func linkedRiskActionRow(action: ProjectLinkedRiskAction) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(Self.linkedActionStatusColor(action.status))
                .frame(width: 8, height: 8)
            Text(action.title)
                .font(.custom("Inter-Medium", size: 13))
                .foregroundColor(Color.Brand.text)
                .lineLimit(2)
            Spacer(minLength: 8)
            linkedActionSeverityBadge(severity: action.severity)
        }
    }

    private func linkedActionSeverityBadge(severity: String) -> some View {
        let (label, fg, bg) = Self.linkedActionSeverityStyle(for: severity)
        return Text(label)
            .font(.custom("Inter-SemiBold", size: 10))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .foregroundColor(fg)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var linkedRiskActionsActionButton: some View {
        let isLoading = viewModel.linkedRiskActionsPhase == .loading
        let hasResult = viewModel.linkedRiskActionsPhase == .loaded
        let hasEmptyOrNoSource = viewModel.linkedRiskActionsPhase == .empty
            || viewModel.linkedRiskActionsPhase == .noRiskAnalysisSource
        let hasError = viewModel.linkedRiskActionsErrorMessage != nil
        let label: String = {
            if isLoading { return "Checking…" }
            if hasError { return "Try again" }
            if hasResult || hasEmptyOrNoSource { return "Refresh" }
            return "Check for linked actions"
        }()

        HStack {
            Spacer()
            Button {
                Task { await viewModel.refreshLinkedRiskActions() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "link")
                    }
                    Text(label)
                        .font(.custom("Inter-SemiBold", size: 13))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.Brand.primary)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            // Prevent double-tap while fetching; lock out while a delete is in flight so
            // read + destructive actions can't race. Mirrors the 2.2 / 2.3 button rules.
            .disabled(isLoading || viewModel.isDeleting)
        }
    }

    /// Status-dot palette. Web uses emerald for resolved, blue for in_progress, amber for
    /// open, gray for everything else (see `page.tsx` lines 707-712). iOS maps to brand
    /// tokens where available and falls back to SwiftUI semantic colors otherwise.
    /// Unknown status values fall through to the neutral textSecondary tone so the row
    /// still renders honestly.
    private static func linkedActionStatusColor(_ status: String) -> Color {
        switch status {
        case "resolved": return Color.green
        case "in_progress": return Color.blue
        case "open": return Color.Brand.warning
        case "acknowledged": return Color.Brand.primary
        case "dismissed": return Color.Brand.textSecondary
        default: return Color.Brand.textSecondary
        }
    }

    /// Severity capsule palette. Web uses red for high, amber for medium, green for low
    /// (see `page.tsx` lines 715-720). `unknown` / unrecognized values render neutrally
    /// rather than being treated as "low" (same posture as 2.3 risk-level `.unknown`).
    private static func linkedActionSeverityStyle(for severity: String) -> (String, Color, Color) {
        switch severity {
        case "high":
            return ("High", .white, Color.red)
        case "medium":
            return ("Med", Color.Brand.warning, Color.Brand.warning.opacity(0.18))
        case "low":
            return ("Low", Color.Brand.primary, Color.Brand.primaryLight)
        default:
            return (severity.capitalized.isEmpty ? "Unknown" : severity.capitalized,
                    Color.Brand.textSecondary,
                    Color.gray.opacity(0.15))
        }
    }

    // MARK: - 2.5 Resolution Feedback foundation section

    /// Detail-page entry for the 2.5 Resolution Feedback foundation. Aggregates the same
    /// `risk_actions` rows that the 2.4 section lists, anchored to the same
    /// `project_risk_summaries.id`. Read-only — all write paths (writing new risk actions,
    /// closing resolutions, governance interventions) stay web-only for this round.
    ///
    /// State machine (devprompt §3.C):
    /// - `.idle`: "Check for resolution feedback" button + subtitle explaining read-only posture.
    /// - `.loading`: button flips to "Checking…" with inline `ProgressView`, disabled.
    /// - `.noRiskAnalysisSource`: honest hint identical in intent to 2.4's same state —
    ///     distinguishes "no analysis yet" from "analysis exists but no actions".
    /// - `.empty`: honest hint "No risk actions tracked yet for this analysis, so there's
    ///     no resolution feedback to aggregate."
    /// - `.loaded`: counts row + governance banner (if any) + dominant category + top-3
    ///     recent resolutions (matches Web's slice(0, 3)).
    /// - Failure: scoped warning row via `summaryErrorRow(message:)`; any prior snapshot
    ///     stays visible below so a flaky call doesn't wipe valid context.
    /// - Denied: handled by `applyDeniedState()` which resets the phase to `.idle`; the
    ///     detail view itself is already hidden behind `deniedStateView`.
    ///
    /// Web parity note: `getProjectRiskResolutionSummary(projectId)` is a server action
    /// with no HTTP exposure, but it makes no `askAI()` / `decryptApiKey()` call — all
    /// aggregation is client-side over a limit-50 PostgREST read that iOS can replicate
    /// directly under the same org-scoped RLS that gates other risk reads. No source-of-
    /// truth discrepancy this round.
    private var resolutionFeedbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Resolution Feedback")
                    .font(.custom("Outfit-SemiBold", size: 16))
                    .foregroundColor(Color.Brand.text)
                Spacer()
                if viewModel.resolutionFeedbackPhase == .loaded,
                   let feedback = viewModel.resolutionFeedback {
                    Text("\(feedback.total) tracked")
                        .font(.custom("Inter-Medium", size: 11))
                        .foregroundColor(Color.Brand.textSecondary)
                }
            }

            Text("Read-only · resolution write-back and governance interventions are only available on the web.")
                .font(.custom("Inter-Regular", size: 11))
                .foregroundColor(Color.Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = viewModel.resolutionFeedbackErrorMessage {
                summaryErrorRow(message: errorMessage)
            }

            resolutionFeedbackBody

            resolutionFeedbackActionButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    @ViewBuilder
    private var resolutionFeedbackBody: some View {
        switch viewModel.resolutionFeedbackPhase {
        case .idle, .loading:
            EmptyView()

        case .noRiskAnalysisSource:
            Text("No risk analysis exists for this project yet. Run one from the web dashboard first, then come back to view its resolution feedback here.")
                .font(.custom("Inter-Regular", size: 12))
                .foregroundColor(Color.Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

        case .empty:
            Text("No risk actions tracked yet for this analysis, so there's no resolution feedback to aggregate.")
                .font(.custom("Inter-Regular", size: 12))
                .foregroundColor(Color.Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

        case .loaded:
            if let feedback = viewModel.resolutionFeedback {
                VStack(alignment: .leading, spacing: 12) {
                    resolutionCountsRow(feedback: feedback)
                    if feedback.governanceSignal != .none || feedback.isProneToReopen {
                        governanceBanner(feedback: feedback)
                    }
                    if let category = feedback.dominantCategory, !category.isEmpty {
                        dominantCategoryRow(category: category)
                    }
                    if !feedback.recentResolutions.isEmpty {
                        recentResolutionsList(resolutions: feedback.recentResolutions)
                    }
                }
            }
        }
    }

    private func resolutionCountsRow(feedback: ProjectResolutionFeedback) -> some View {
        // Stats row mirrors Web's badge strip (page.tsx 725-779): resolved / dismissed /
        // active / follow-up / reopened. Horizontal scroll avoids compression on narrow
        // widths when all five badges are populated.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                resolutionStatBadge(label: "Resolved", count: feedback.resolved,
                                    fg: Color.Brand.primary, bg: Color.Brand.primaryLight)
                resolutionStatBadge(label: "Dismissed", count: feedback.dismissed,
                                    fg: Color.Brand.textSecondary, bg: Color.gray.opacity(0.15))
                resolutionStatBadge(label: "Active", count: feedback.active,
                                    fg: Color.Brand.warning, bg: Color.Brand.warning.opacity(0.18))
                resolutionStatBadge(label: "Follow-up", count: feedback.followUpRequired,
                                    fg: Color.Brand.warning, bg: Color.Brand.warning.opacity(0.18))
                resolutionStatBadge(label: "Reopened", count: feedback.reopenedCount,
                                    fg: .white, bg: Color.red.opacity(0.85))
            }
        }
    }

    private func resolutionStatBadge(label: String, count: Int, fg: Color, bg: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.custom("Inter-SemiBold", size: 13))
            Text(label)
                .font(.custom("Inter-Medium", size: 11))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(bg)
        .foregroundColor(fg)
        .clipShape(Capsule())
    }

    private func governanceBanner(feedback: ProjectResolutionFeedback) -> some View {
        // Governance intervention status mirrors Web's "干预已生效" / "待治理干预" badges
        // (page.tsx 780-796) with **effective-first** priority: when both conditions hold,
        // `.interventionEffective` wins. The predictive "易重开" rose-pulse badge
        // (lines 754-758) is an **independent** rail — it renders whenever
        // `isProneToReopen` fires, including alongside `.interventionEffective`. To keep
        // the semantics distinct the subline uses Brand.warning regardless of the
        // governance tone, so a green "Intervention effective" banner cannot mute the
        // warning color of the prone-to-reopen subline.
        let (title, tint, bg) = Self.governanceStyle(for: feedback.governanceSignal)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: feedback.governanceSignal == .interventionEffective
                      ? "checkmark.shield.fill"
                      : "exclamationmark.shield.fill")
                    .foregroundColor(tint)
                Text(title)
                    .font(.custom("Inter-SemiBold", size: 12))
                    .foregroundColor(tint)
            }
            if feedback.isProneToReopen {
                Text("Prone to reopen · \(feedback.reopenedCount) reopened action(s) still have unresolved work.")
                    .font(.custom("Inter-Regular", size: 11))
                    .foregroundColor(Color.Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dominantCategoryRow(category: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.system(size: 11))
                .foregroundColor(Color.Brand.textSecondary)
            Text("Dominant category")
                .font(.custom("Inter-Medium", size: 11))
                .foregroundColor(Color.Brand.textSecondary)
            Text(Self.humanize(category))
                .font(.custom("Inter-SemiBold", size: 12))
                .foregroundColor(Color.Brand.text)
        }
    }

    private func recentResolutionsList(resolutions: [ProjectResolutionFeedback.RecentResolution]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent resolutions")
                .font(.custom("Inter-SemiBold", size: 12))
                .foregroundColor(Color.Brand.textSecondary)
                .padding(.top, 2)
            ForEach(Array(resolutions.prefix(3).enumerated()), id: \.offset) { _, resolution in
                recentResolutionRow(resolution: resolution)
            }
        }
    }

    private func recentResolutionRow(resolution: ProjectResolutionFeedback.RecentResolution) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Self.resolutionStatusColor(resolution.status))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(resolution.title)
                    .font(.custom("Inter-Medium", size: 13))
                    .foregroundColor(Color.Brand.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let effectiveness = resolution.effectiveness, !effectiveness.isEmpty {
                        effectivenessCapsule(effectiveness: effectiveness)
                    }
                    if let dateText = resolvedAtDisplayDate(resolution.resolvedAtRaw) {
                        Text(dateText)
                            .font(.custom("Inter-Regular", size: 11))
                            .foregroundColor(Color.Brand.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func effectivenessCapsule(effectiveness: String) -> some View {
        let (label, fg, bg) = Self.effectivenessStyle(for: effectiveness)
        return Text(label)
            .font(.custom("Inter-SemiBold", size: 10))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .foregroundColor(fg)
            .clipShape(Capsule())
    }

    /// Parses the raw ISO 8601 `timestamptz` string PostgREST returns for `risk_actions.resolved_at`
    /// into a display date. Uses `ISO8601DateFormatter` with/without fractional seconds so both
    /// `2026-04-16T12:34:56+00:00` and `2026-04-16T12:34:56.789+00:00` decode. Returns `nil` on
    /// any parse failure — the UI layer then drops the date element rather than crashing render.
    private func resolvedAtDisplayDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let parsers: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                return f
            }()
        ]
        for parser in parsers {
            if let date = parser.date(from: raw) {
                return Self.generatedAtFormatter.string(from: date)
            }
        }
        return nil
    }

    @ViewBuilder
    private var resolutionFeedbackActionButton: some View {
        let isLoading = viewModel.resolutionFeedbackPhase == .loading
        let hasResult = viewModel.resolutionFeedbackPhase == .loaded
        let hasEmptyOrNoSource = viewModel.resolutionFeedbackPhase == .empty
            || viewModel.resolutionFeedbackPhase == .noRiskAnalysisSource
        let hasError = viewModel.resolutionFeedbackErrorMessage != nil
        let label: String = {
            if isLoading { return "Checking…" }
            if hasError { return "Try again" }
            if hasResult || hasEmptyOrNoSource { return "Refresh" }
            return "Check for resolution feedback"
        }()

        HStack {
            Spacer()
            Button {
                Task { await viewModel.refreshResolutionFeedback() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.seal")
                    }
                    Text(label)
                        .font(.custom("Inter-SemiBold", size: 13))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.Brand.primary)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            // Mirrors the 2.2 / 2.3 / 2.4 button rules: prevent double-tap while in flight
            // and lock out while a delete is running so read + destructive don't race.
            .disabled(isLoading || viewModel.isDeleting)
        }
    }

    /// Status-dot palette for recent resolution rows. Web only surfaces rows with status in
    /// {resolved, dismissed} in the recent list, so the palette is narrow by design; any
    /// other value falls through to neutral textSecondary rather than being reassigned.
    private static func resolutionStatusColor(_ status: String) -> Color {
        switch status {
        case "resolved": return Color.green
        case "dismissed": return Color.Brand.textSecondary
        default: return Color.Brand.textSecondary
        }
    }

    /// Effectiveness capsule palette. Web's effectiveness vocabulary per migration 037:
    /// {effective, partial, ineffective, pending}. Unknown values render with a neutral
    /// tone so unexpected server expansion degrades gracefully (same posture as the rest
    /// of the 2.x defensive styling).
    private static func effectivenessStyle(for raw: String) -> (String, Color, Color) {
        switch raw {
        case "effective":
            return ("Effective", Color.Brand.primary, Color.Brand.primaryLight)
        case "partial":
            return ("Partial", Color.Brand.warning, Color.Brand.warning.opacity(0.18))
        case "ineffective":
            return ("Ineffective", .white, Color.red.opacity(0.85))
        case "pending":
            return ("Pending", Color.Brand.textSecondary, Color.gray.opacity(0.15))
        default:
            return (humanize(raw), Color.Brand.textSecondary, Color.gray.opacity(0.15))
        }
    }

    /// Governance banner palette. Mirrors Web's two tones (page.tsx 780-796): a calm
    /// primary-tinted banner for "干预已生效", and a warning-tinted banner for "待治理干预".
    /// When `.none` is passed (caller guard), falls through to a neutral tone; callers
    /// already guard on `!= .none` so this is dead-code defensive.
    private static func governanceStyle(for signal: ProjectResolutionFeedback.GovernanceSignal)
        -> (String, Color, Color)
    {
        switch signal {
        case .interventionEffective:
            return ("Intervention effective",
                    Color.Brand.primary,
                    Color.Brand.primaryLight.opacity(0.55))
        case .needsIntervention:
            return ("Needs governance intervention",
                    Color.Brand.warning,
                    Color.Brand.warning.opacity(0.18))
        case .none:
            return ("Neutral",
                    Color.Brand.textSecondary,
                    Color.gray.opacity(0.10))
        }
    }
}
