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
            BsColor.surfaceSecondary
                .ignoresSafeArea()

            Group {
                if viewModel.accessOutcome == .denied {
                    deniedStateView
                } else if let project = viewModel.project {
                    detailScroll(project: project)
                } else if viewModel.isLoading {
                    ProgressView()
                        .tint(BsColor.brandAzure)
                } else if let error = viewModel.errorMessage {
                    errorStateView(message: error)
                } else {
                    ProgressView()
                        .tint(BsColor.brandAzure)
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
                            .foregroundColor(BsColor.brandAzure)
                    }
                    .accessibilityLabel("编辑项目")
                    .disabled(viewModel.isDeleting)
                }
                // 2.0: delete entry. Same access gate as the edit button — a denied caller
                // must never see a destructive affordance for a project they can't read.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(BsColor.warning)
                    }
                    .accessibilityLabel("删除项目")
                    .disabled(viewModel.isDeleting)
                }
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading && viewModel.project != nil {
                ProgressView()
                    .tint(BsColor.brandAzure)
                    .padding(.top, 8)
            }
        }
        // 2.0: dimmed progress overlay covers the scroll while a delete is in flight to
        // prevent accidental taps on child content. Matches the edit-sheet overlay pattern.
        .overlay {
            if viewModel.isDeleting {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView("正在删除…")
                    .tint(BsColor.brandAzure)
                    .padding()
                    .background(BsColor.surfacePrimary)
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
            "确定删除这个项目吗？",
            isPresented: $isShowingDeleteConfirm,
            titleVisibility: .visible
        ) {
            if let project = viewModel.project {
                Button("删除 “\(project.name)”", role: .destructive) {
                    Task { await confirmDelete() }
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            if let project = viewModel.project {
                Text("将永久删除 “\(project.name)” 及其全部成员，此操作不可撤销。")
            } else {
                Text("将永久删除该项目，此操作不可撤销。")
            }
        }
        .alert(
            "删除失败",
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { newValue in if !newValue { viewModel.deleteErrorMessage = nil } }
            ),
            actions: {
                Button("好的", role: .cancel) { viewModel.deleteErrorMessage = nil }
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
        if viewModel.accessOutcome == .denied { return "项目" }
        return viewModel.project?.name ?? "项目"
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
                .font(BsTypography.brandTitle)
                .foregroundColor(BsColor.ink)

            statusBadge(status: project.status)
        }
    }

    private func statusBadge(status: Project.ProjectStatus) -> some View {
        let (label, fg, bg) = Self.statusStyle(for: status)
        return Text(label)
            .font(BsTypography.inter(12, weight: "SemiBold"))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(bg)
            .foregroundColor(fg)
            .clipShape(Capsule())
    }

    private func metadataSection(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let start = project.startDate {
                metaRow(icon: "calendar", label: "开始", value: Self.dateFormatter.string(from: start))
            }
            if let end = project.endDate {
                metaRow(icon: "calendar.badge.clock", label: "截止", value: Self.dateFormatter.string(from: end))
            }
            // 1.7: owner row now prefers the joined profile's full_name. If owner fetch failed
            // (recorded in `enrichmentErrors[.owner]`) we fall back to the raw UUID rather than
            // hiding the row, so the detail still shows *something* for the owner field.
            ownerMetaRow(project: project)
            if let createdAt = project.createdAt {
                metaRow(icon: "clock", label: "创建", value: Self.dateFormatter.string(from: createdAt))
            }
        }
        .padding(16)
        .background(BsColor.surfacePrimary)
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
            ownerMetaRowLayout(label: "所有者", value: ownerFullName, avatarUrl: avatarUrl)
        } else if let ownerId = project.ownerId {
            // Either owner hasn't loaded yet, profile has no full_name, or the owner fetch
            // recorded an error. Keep the UUID visible so the field isn't silently empty.
            ownerMetaRowLayout(label: "所有者", value: ownerId.uuidString, avatarUrl: avatarUrl)
        }
    }

    /// Owner-row layout: inline avatar (or person icon fallback) + label + value. Mirrors the
    /// shape of `metaRow` so the metadata card stays visually consistent.
    private func ownerMetaRowLayout(label: String, value: String, avatarUrl: String?) -> some View {
        HStack(spacing: 12) {
            ownerAvatarView(urlString: avatarUrl, diameter: 22)
            Text(label)
                .font(BsTypography.caption)
                .foregroundColor(BsColor.inkMuted)
            Spacer()
            Text(value)
                .font(BsTypography.inter(13, weight: "Regular"))
                .foregroundColor(BsColor.ink)
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
            .overlay(Circle().stroke(BsColor.brandAzureLight.opacity(0.4), lineWidth: 0.5))
        } else {
            ownerAvatarPlaceholder
                .frame(width: diameter, height: diameter)
        }
    }

    private var ownerAvatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(BsColor.brandAzure.opacity(0.75))
    }

    private func metaRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(BsColor.brandAzure)
                .frame(width: 20)
            Text(label)
                .font(BsTypography.caption)
                .foregroundColor(BsColor.inkMuted)
            Spacer()
            Text(value)
                .font(BsTypography.inter(13, weight: "Regular"))
                .foregroundColor(BsColor.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func progressSection(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("进度")
                    .font(BsTypography.outfit(16, weight: "SemiBold"))
                    .foregroundColor(BsColor.ink)
                Spacer()
                Text("\(project.progress)%")
                    .font(BsTypography.inter(14, weight: "SemiBold"))
                    .foregroundColor(BsColor.brandAzure)
            }
            ProgressView(value: Double(min(max(project.progress, 0), 100)) / 100.0)
                .progressViewStyle(.linear)
                .tint(BsColor.brandAzure)
        }
        .padding(16)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    private func descriptionSection(description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("项目描述")
                .font(BsTypography.outfit(16, weight: "SemiBold"))
                .foregroundColor(BsColor.ink)
            Text(description)
                .font(BsTypography.bodySmall)
                .foregroundColor(BsColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - 1.7 read-only enrichment sections

    /// Compact list of up to 50 tasks attached to this project (Web parity: `fetchProjectDetail()`
    /// `tasks` sub-select). Read-only; no navigation, no edit — that belongs to the Tasks module.
    private var tasksSection: some View {
        enrichmentCard(
            title: "任务",
            subtitle: tasksSubtitle,
            errorMessage: viewModel.enrichmentErrors[.tasks]
        ) {
            if viewModel.tasks.isEmpty && viewModel.enrichmentErrors[.tasks] == nil {
                emptyLine("暂无任务。")
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
                                    .font(BsTypography.caption)
                                    .foregroundColor(BsColor.ink)
                                    .lineLimit(2)
                                Text(taskMetaLine(for: task))
                                    .font(BsTypography.inter(11, weight: "Regular"))
                                    .foregroundColor(BsColor.inkMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if viewModel.tasks.count > 8 {
                        Text("还有 \(viewModel.tasks.count - 8) 条")
                            .font(BsTypography.inter(11, weight: "Medium"))
                            .foregroundColor(BsColor.inkMuted)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var tasksSubtitle: String? {
        guard viewModel.enrichmentErrors[.tasks] == nil else { return nil }
        return viewModel.tasks.isEmpty ? nil : "共 \(viewModel.tasks.count) 条"
    }

    /// Compact list of up to 10 recent daily logs (Web parity: `fetchProjectDetail()`
    /// `recent_daily_logs` sub-select).
    private var dailyLogsSection: some View {
        enrichmentCard(
            title: "近期日报",
            subtitle: dailyLogsSubtitle,
            errorMessage: viewModel.enrichmentErrors[.dailyLogs]
        ) {
            if viewModel.dailyLogs.isEmpty && viewModel.enrichmentErrors[.dailyLogs] == nil {
                emptyLine("暂无日报。")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.dailyLogs.prefix(5)) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(log.date)
                                    .font(BsTypography.inter(12, weight: "SemiBold"))
                                    .foregroundColor(BsColor.brandAzure)
                                if let authorLine = authorLine(forUserId: log.userId) {
                                    Text("·")
                                        .font(BsTypography.inter(11, weight: "Regular"))
                                        .foregroundColor(BsColor.inkMuted)
                                    Text(authorLine)
                                        .font(BsTypography.inter(11, weight: "Medium"))
                                        .foregroundColor(BsColor.inkMuted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Text(log.content)
                                .font(BsTypography.inter(13, weight: "Regular"))
                                .foregroundColor(BsColor.ink)
                                .lineLimit(3)
                            if let blockers = log.blockers, !blockers.isEmpty {
                                Text("阻塞：\(blockers)")
                                    .font(BsTypography.inter(11, weight: "Regular"))
                                    .foregroundColor(BsColor.warning)
                                    .lineLimit(2)
                            }
                        }
                    }
                    if viewModel.dailyLogs.count > 5 {
                        Text("还有 \(viewModel.dailyLogs.count - 5) 条")
                            .font(BsTypography.inter(11, weight: "Medium"))
                            .foregroundColor(BsColor.inkMuted)
                    }
                }
            }
        }
    }

    private var dailyLogsSubtitle: String? {
        guard viewModel.enrichmentErrors[.dailyLogs] == nil else { return nil }
        return viewModel.dailyLogs.isEmpty ? nil : "最近 \(viewModel.dailyLogs.count) 条"
    }

    /// Compact list of up to 5 recent weekly summaries (Web parity: `fetchProjectDetail()`
    /// `weekly_summaries` sub-select where `project_ids @> [projectId]`).
    private var weeklySummariesSection: some View {
        enrichmentCard(
            title: "近期周报",
            subtitle: weeklySubtitle,
            errorMessage: viewModel.enrichmentErrors[.weeklySummaries]
        ) {
            if viewModel.weeklySummaries.isEmpty && viewModel.enrichmentErrors[.weeklySummaries] == nil {
                emptyLine("暂无周报。")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.weeklySummaries.prefix(3)) { week in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("\(week.weekStart) 当周")
                                    .font(BsTypography.inter(12, weight: "SemiBold"))
                                    .foregroundColor(BsColor.brandAzure)
                                if let authorLine = authorLine(forUserId: week.userId) {
                                    Text("·")
                                        .font(BsTypography.inter(11, weight: "Regular"))
                                        .foregroundColor(BsColor.inkMuted)
                                    Text(authorLine)
                                        .font(BsTypography.inter(11, weight: "Medium"))
                                        .foregroundColor(BsColor.inkMuted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Text(week.summary)
                                .font(BsTypography.inter(13, weight: "Regular"))
                                .foregroundColor(BsColor.ink)
                                .lineLimit(3)
                            if let highlights = week.highlights, !highlights.isEmpty {
                                Text("亮点：\(highlights)")
                                    .font(BsTypography.inter(11, weight: "Regular"))
                                    .foregroundColor(BsColor.inkMuted)
                                    .lineLimit(2)
                            }
                        }
                    }
                    if viewModel.weeklySummaries.count > 3 {
                        Text("还有 \(viewModel.weeklySummaries.count - 3) 条")
                            .font(BsTypography.inter(11, weight: "Medium"))
                            .foregroundColor(BsColor.inkMuted)
                    }
                }
            }
        }
    }

    private var weeklySubtitle: String? {
        guard viewModel.enrichmentErrors[.weeklySummaries] == nil else { return nil }
        return viewModel.weeklySummaries.isEmpty ? nil : "共 \(viewModel.weeklySummaries.count) 条"
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
                    .font(BsTypography.outfit(16, weight: "SemiBold"))
                    .foregroundColor(BsColor.ink)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(BsTypography.inter(11, weight: "Medium"))
                        .foregroundColor(BsColor.inkMuted)
                }
            }
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(BsColor.warning)
                    Text("加载失败：\(errorMessage)")
                        .font(BsTypography.inter(12, weight: "Regular"))
                        .foregroundColor(BsColor.warning)
                        .lineLimit(3)
                }
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(BsTypography.inter(12, weight: "Regular"))
            .foregroundColor(BsColor.inkMuted)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(BsColor.warning)
            Text(message)
                .font(BsTypography.caption)
                .foregroundColor(BsColor.warning)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(BsColor.warning.opacity(0.10))
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
        Text("生成新的风险分析以及处理结果写回（关闭 / 重开 / 有效性）暂仅支持 Web 端，iOS 后续版本补齐。")
            .font(BsTypography.inter(12, weight: "Regular"))
            .foregroundColor(BsColor.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(BsColor.brandAzureLight.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 2.2 AI summary foundation section

    /// Detail-page entry for the AI summary section. Phase 6.1 replaced the local 2.2
    /// facts-synthesis foundation with a direct HTTP call to the Web bridge at
    /// `POST /api/ai/project-summary`, so the rendered content is now a server-generated
    /// structured snapshot with five sections: 简述 / 已完成亮点 / 进行中 / 下一步 / 风险提示.
    ///
    /// State machine:
    /// - idle: single "生成摘要" button.
    /// - generating: inline `ProgressView` + "生成中…" label, button disabled.
    /// - success: structured sections rendered below + "重新生成" button.
    /// - error: isolated warning row + "重试" button.
    private var aiSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI 项目摘要")
                    .font(BsTypography.outfit(16, weight: "SemiBold"))
                    .foregroundColor(BsColor.ink)
                Spacer()
                if let caption = summaryProvenanceCaption(for: viewModel.projectSummary) {
                    Text(caption)
                        .font(BsTypography.inter(11, weight: "Medium"))
                        .foregroundColor(BsColor.inkMuted)
                }
            }

            Text("由 Web 端 AI 服务生成 · 涵盖进度简述、已完成亮点、进行中事项、下一步与风险提示。")
                .font(BsTypography.inter(11, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = viewModel.summaryErrorMessage {
                summaryErrorRow(message: errorMessage)
            } else if let summary = viewModel.projectSummary {
                projectSummaryContent(summary: summary)
            }

            summaryActionButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    @ViewBuilder
    private func projectSummaryContent(summary: ProjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !summary.snapshotSummary.isEmpty {
                summarySection(title: "简述", body: summary.snapshotSummary)
            }
            if !summary.completedHighlights.isEmpty {
                summaryBulletSection(title: "已完成亮点", items: summary.completedHighlights)
            }
            if !summary.inProgress.isEmpty {
                summaryBulletSection(title: "进行中", items: summary.inProgress)
            }
            if !summary.nextSteps.isEmpty {
                summaryBulletSection(title: "下一步", items: summary.nextSteps)
            }
            if !summary.riskNotes.isEmpty {
                summaryBulletSection(title: "风险提示", items: summary.riskNotes)
            }
        }
    }

    @ViewBuilder
    private func summarySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(BsTypography.inter(12, weight: "SemiBold"))
                .foregroundColor(BsColor.inkMuted)
            Text(body)
                .font(BsTypography.inter(13, weight: "Regular"))
                .foregroundColor(BsColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func summaryBulletSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(BsTypography.inter(12, weight: "SemiBold"))
                .foregroundColor(BsColor.inkMuted)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(BsTypography.inter(13, weight: "Regular"))
                        .foregroundColor(BsColor.inkMuted)
                    Text(item)
                        .font(BsTypography.inter(13, weight: "Regular"))
                        .foregroundColor(BsColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func summaryProvenanceCaption(for summary: ProjectSummary?) -> String? {
        guard let summary else { return nil }
        var parts: [String] = []
        if let raw = summary.generatedAt, let date = Self.parseISOTimestamp(raw) {
            parts.append("生成于 " + Self.generatedAtFormatter.string(from: date))
        }
        if let model = summary.modelUsed, !model.isEmpty {
            parts.append("模型：\(model)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func parseISOTimestamp(_ raw: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: raw)
    }

    @ViewBuilder
    private var summaryActionButton: some View {
        let hasResult = viewModel.projectSummary != nil
        let hasError = viewModel.summaryErrorMessage != nil
        let label: String = {
            if viewModel.isGeneratingSummary { return "生成中…" }
            if hasError { return "重试" }
            if hasResult { return "重新生成" }
            return "生成摘要"
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
                        .font(BsTypography.inter(13, weight: "SemiBold"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(BsColor.brandAzure)
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
                .foregroundColor(BsColor.warning)
            Text(message)
                .font(BsTypography.inter(12, weight: "Regular"))
                .foregroundColor(BsColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(BsColor.warning.opacity(0.10))
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
                Text("AI 风险分析")
                    .font(BsTypography.outfit(16, weight: "SemiBold"))
                    .foregroundColor(BsColor.ink)
                Spacer()
                if let analysis = viewModel.riskAnalysis {
                    riskLevelBadge(level: analysis.riskLevel)
                }
            }

            Text("由 Web 端 AI 服务生成 · 包含整体风险等级、摘要说明、逐条风险项与处置建议。")
                .font(BsTypography.inter(11, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = viewModel.riskAnalysisErrorMessage {
                summaryErrorRow(message: errorMessage)
            } else if let analysis = viewModel.riskAnalysis {
                riskAnalysisContent(analysis: analysis)
            } else if viewModel.riskAnalysisNotYetGenerated {
                Text("Web 端尚未为该项目生成风险分析。")
                    .font(BsTypography.inter(12, weight: "Regular"))
                    .foregroundColor(BsColor.inkMuted)
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
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .confirmationDialog(
            "将当前风险分析转为风险动作？",
            isPresented: $isShowingRiskActionSyncConfirm,
            titleVisibility: .visible,
            presenting: pendingRiskActionDraft
        ) { draft in
            Button("创建风险动作") {
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
            Button("取消", role: .cancel) {
                pendingRiskActionDraft = nil
            }
        } message: { draft in
            // Dialog preview mirrors the three user-visible inputs Web sends into
            // syncRiskFromDetection: title, trimmed detail, severity. A new risk_actions
            // row will be created with status 'open' and linked to the current analysis.
            Text("""
            将创建一条新的风险动作，并关联到该项目的风险分析。

            • 标题：\(draft.title)
            • 严重度：\(Self.riskActionSeverityLabel(draft.severity))
            • 详情：\(draft.detail.isEmpty ? "—" : draft.detail)
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
                        Text(isSyncing ? "转换中…" : "转为风险动作")
                            .font(BsTypography.inter(13, weight: "SemiBold"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(canSyncRiskAction ? BsColor.warning : BsColor.inkMuted.opacity(0.4))
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
                Text("转为风险动作需要管理员或经理权限。")
                    .font(BsTypography.inter(11, weight: "Regular"))
                    .foregroundColor(BsColor.inkMuted)
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
                        .foregroundColor(BsColor.brandAzure)
                    Text("已转为风险动作，并关联到本次分析。")
                        .font(BsTypography.inter(12, weight: "Regular"))
                        .foregroundColor(BsColor.brandAzure)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(BsColor.brandAzureLight.opacity(0.55))
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
    // D.2a: Chinese severity labels for the confirmation dialog.
    private static func riskActionSeverityLabel(_ severity: String) -> String {
        switch severity {
        case "high": return "高"
        case "medium": return "中"
        case "low": return "低"
        default: return severity.capitalized
        }
    }

    @ViewBuilder
    private func riskAnalysisContent(analysis: ProjectRiskAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !analysis.summary.isEmpty {
                Text(analysis.summary)
                    .font(BsTypography.inter(13, weight: "Regular"))
                    .foregroundColor(BsColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !analysis.risks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("风险项")
                        .font(BsTypography.inter(12, weight: "SemiBold"))
                        .foregroundColor(BsColor.inkMuted)
                    ForEach(Array(analysis.risks.enumerated()), id: \.offset) { _, item in
                        riskItemRow(item: item)
                    }
                }
            }

            if let caption = riskAnalysisProvenanceCaption(for: analysis) {
                Text(caption)
                    .font(BsTypography.inter(11, weight: "Medium"))
                    .foregroundColor(BsColor.inkMuted)
            }
        }
    }

    @ViewBuilder
    private func riskItemRow(item: ProjectRiskAnalysis.RiskItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                riskCategoryChip(category: item.category)
                riskSeverityChip(severity: item.severity)
                Spacer()
            }
            if !item.title.isEmpty {
                Text(item.title)
                    .font(BsTypography.inter(13, weight: "SemiBold"))
                    .foregroundColor(BsColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.description.isEmpty {
                Text(item.description)
                    .font(BsTypography.inter(12, weight: "Regular"))
                    .foregroundColor(BsColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.suggestedAction.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text("建议：")
                        .font(BsTypography.inter(12, weight: "SemiBold"))
                        .foregroundColor(BsColor.brandAzure)
                    Text(item.suggestedAction)
                        .font(BsTypography.inter(12, weight: "Regular"))
                        .foregroundColor(BsColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(BsColor.brandAzureLight.opacity(0.20))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func riskCategoryChip(category: String) -> some View {
        let label: String = {
            switch category.lowercased() {
            case "schedule": return "进度"
            case "progress": return "进展"
            case "resource": return "资源"
            case "blocker": return "阻塞"
            default: return "其他"
            }
        }()
        return Text(label)
            .font(BsTypography.inter(10, weight: "Medium"))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(BsColor.brandAzure.opacity(0.15))
            .foregroundColor(BsColor.brandAzure)
            .clipShape(Capsule())
    }

    private func riskSeverityChip(severity: String) -> some View {
        let lower = severity.lowercased()
        let (label, fg, bg): (String, Color, Color) = {
            switch lower {
            case "critical": return ("严重", .white, BsColor.danger)
            case "high":     return ("高", .white, BsColor.warning)
            case "medium":   return ("中", BsColor.warning, BsColor.warning.opacity(0.18))
            case "low":      return ("低", BsColor.brandAzure, BsColor.brandAzureLight)
            default:         return (severity.capitalized, BsColor.inkMuted, BsColor.inkMuted.opacity(0.15))
            }
        }()
        return Text(label)
            .font(BsTypography.inter(10, weight: "SemiBold"))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .foregroundColor(fg)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var riskAnalysisActionButton: some View {
        let hasResult = viewModel.riskAnalysis != nil
        let hasError = viewModel.riskAnalysisErrorMessage != nil
        let label: String = {
            if viewModel.isLoadingRiskAnalysis { return "生成中…" }
            if hasError { return "重试" }
            if hasResult { return "重新生成" }
            return "生成风险分析"
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
                        .font(BsTypography.inter(13, weight: "SemiBold"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(BsColor.brandAzure)
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
            .font(BsTypography.inter(11, weight: "SemiBold"))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bg)
            .foregroundColor(fg)
            .clipShape(Capsule())
    }

    private func riskAnalysisProvenanceCaption(for analysis: ProjectRiskAnalysis) -> String? {
        var parts: [String] = []
        if let generatedAt = analysis.generatedAt {
            parts.append("生成于 " + Self.generatedAtFormatter.string(from: generatedAt))
        }
        if let model = analysis.model, !model.isEmpty {
            parts.append("模型：\(model)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Risk-level palette. Stays within existing brand tokens for low/medium/high; uses
    /// SwiftUI's built-in `.red` for critical because there's no dedicated danger token in
    /// `Color.Brand`. Unknown values (e.g. Web wrote an unrecognized level) render neutrally
    /// rather than pretending to be "low".
    // D.2a: Chinese labels for risk-level badges (mirrors Web `🟢 低 / 🟡 中 / 🟠 高 / 🔴 严重`).
    private static func riskLevelStyle(for level: ProjectRiskAnalysis.RiskLevel) -> (String, Color, Color) {
        switch level {
        case .low:
            return ("低风险", BsColor.brandAzure, BsColor.brandAzureLight)
        case .medium:
            return ("中风险", BsColor.warning, BsColor.warning.opacity(0.18))
        case .high:
            return ("高风险", .white, BsColor.warning)
        case .critical:
            return ("严重风险", .white, BsColor.danger)
        case .unknown:
            return ("未知", BsColor.inkMuted, BsColor.inkMuted.opacity(0.15))
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
                    .fill(BsColor.warning.opacity(0.12))
                    .frame(width: 96, height: 96)
                Image(systemName: "lock.shield")
                    .font(.system(size: 36))
                    .foregroundColor(BsColor.warning)
            }
            Text("无权访问此项目")
                .font(BsTypography.sectionTitle)
                .foregroundColor(BsColor.ink)
            Text("你没有查看此项目的权限。可请管理员在 Web 端将你添加为项目成员。")
                .font(BsTypography.bodySmall)
                .foregroundColor(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        .padding(.horizontal, 24)
    }

    private func errorStateView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(BsColor.warning)
            Text("项目加载失败")
                .font(BsTypography.outfit(18, weight: "SemiBold"))
                .foregroundColor(BsColor.ink)
            Text(message)
                .font(BsTypography.inter(13, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await reload() }
            } label: {
                Text("重试")
                    .font(BsTypography.inter(14, weight: "SemiBold"))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(BsColor.brandAzure)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 24)
    }

    // MARK: - Styling helpers

    // D.2a: Chinese labels matching Web STATUS_CFG.
    private static func statusStyle(for status: Project.ProjectStatus) -> (String, Color, Color) {
        switch status {
        case .planning:
            return ("规划中", BsColor.brandAzure, BsColor.brandAzureLight)
        case .active:
            return ("进行中", .white, BsColor.brandAzure)
        case .onHold:
            return ("暂停", BsColor.warning, BsColor.warning.opacity(0.15))
        case .completed:
            return ("已完成", BsColor.inkMuted, BsColor.inkMuted.opacity(0.15))
        case .archived:
            return ("归档", BsColor.inkMuted, BsColor.inkMuted.opacity(0.10))
        }
    }

    /// Loose mapping from the server's `tasks.status` string to a colour dot. Stays tolerant
    /// of unknown status values (the DTO decodes `status` as a raw `String`).
    private static func taskStatusColor(_ status: String) -> Color {
        switch status {
        case "done": return BsColor.brandAzure
        case "in_progress", "review": return BsColor.warning
        default: return BsColor.inkMuted
        }
    }

    private static func humanize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // D.2a: zh_CN locale for date labels in detail view.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        f.locale = Locale(identifier: "zh_CN")
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
                Text("已关联风险动作")
                    .font(BsTypography.outfit(16, weight: "SemiBold"))
                    .foregroundColor(BsColor.ink)
                Spacer()
                if viewModel.linkedRiskActionsPhase == .loaded,
                   !viewModel.linkedRiskActions.isEmpty {
                    Text("\(viewModel.linkedRiskActions.count) linked")
                        .font(BsTypography.inter(11, weight: "Medium"))
                        .foregroundColor(BsColor.inkMuted)
                }
            }

            Text("与当前风险分析关联的动作列表。关闭 / 重开 / 有效性等处理结果写回暂仅支持 Web 端。")
                .font(BsTypography.inter(11, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = viewModel.linkedRiskActionsErrorMessage {
                summaryErrorRow(message: errorMessage)
            }

            linkedRiskActionsBody

            linkedRiskActionsActionButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BsColor.surfacePrimary)
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
            Text("该项目暂无风险分析。请先在 Web 端生成分析，再返回这里查看已关联动作。")
                .font(BsTypography.inter(12, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

        case .empty:
            Text("当前分析尚无关联的风险动作。")
                .font(BsTypography.inter(12, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)

        case .loaded:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.linkedRiskActions.prefix(3)) { action in
                    linkedRiskActionRow(action: action)
                }
                if viewModel.linkedRiskActions.count > 3 {
                    Text("+ \(viewModel.linkedRiskActions.count - 3) more on the web dashboard")
                        .font(BsTypography.inter(11, weight: "Medium"))
                        .foregroundColor(BsColor.inkMuted)
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
                .font(BsTypography.caption)
                .foregroundColor(BsColor.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            linkedActionSeverityBadge(severity: action.severity)
        }
    }

    private func linkedActionSeverityBadge(severity: String) -> some View {
        let (label, fg, bg) = Self.linkedActionSeverityStyle(for: severity)
        return Text(label)
            .font(BsTypography.inter(10, weight: "SemiBold"))
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
            if isLoading { return "加载中…" }
            if hasError { return "重试" }
            if hasResult || hasEmptyOrNoSource { return "刷新" }
            return "查看关联动作"
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
                        .font(BsTypography.inter(13, weight: "SemiBold"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(BsColor.brandAzure)
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
        case "resolved": return BsColor.success
        case "in_progress": return BsColor.brandAzure
        case "open": return BsColor.warning
        case "acknowledged": return BsColor.brandAzure
        case "dismissed": return BsColor.inkMuted
        default: return BsColor.inkMuted
        }
    }

    /// Severity capsule palette. Web uses red for high, amber for medium, green for low
    /// (see `page.tsx` lines 715-720). `unknown` / unrecognized values render neutrally
    /// rather than being treated as "low" (same posture as 2.3 risk-level `.unknown`).
    // D.2a: Chinese severity labels for linked action capsules.
    private static func linkedActionSeverityStyle(for severity: String) -> (String, Color, Color) {
        switch severity {
        case "high":
            return ("高", .white, BsColor.danger)
        case "medium":
            return ("中", BsColor.warning, BsColor.warning.opacity(0.18))
        case "low":
            return ("低", BsColor.brandAzure, BsColor.brandAzureLight)
        default:
            return (severity.capitalized.isEmpty ? "未知" : severity.capitalized,
                    BsColor.inkMuted,
                    BsColor.inkMuted.opacity(0.15))
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
                Text("处理结果回流")
                    .font(BsTypography.outfit(16, weight: "SemiBold"))
                    .foregroundColor(BsColor.ink)
                Spacer()
                if viewModel.resolutionFeedbackPhase == .loaded,
                   let feedback = viewModel.resolutionFeedback {
                    Text("\(feedback.total) tracked")
                        .font(BsTypography.inter(11, weight: "Medium"))
                        .foregroundColor(BsColor.inkMuted)
                }
            }

            Text("只读 · 处理结果写回与治理干预暂仅支持 Web 端。")
                .font(BsTypography.inter(11, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = viewModel.resolutionFeedbackErrorMessage {
                summaryErrorRow(message: errorMessage)
            }

            resolutionFeedbackBody

            resolutionFeedbackActionButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    @ViewBuilder
    private var resolutionFeedbackBody: some View {
        switch viewModel.resolutionFeedbackPhase {
        case .idle, .loading:
            EmptyView()

        case .noRiskAnalysisSource:
            Text("该项目暂无风险分析。请先在 Web 端生成分析，再返回这里查看处理结果回流。")
                .font(BsTypography.inter(12, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

        case .empty:
            Text("当前分析还没有跟踪中的风险动作，暂无处理结果可聚合。")
                .font(BsTypography.inter(12, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
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
                resolutionStatBadge(label: "已解决", count: feedback.resolved,
                                    fg: BsColor.brandAzure, bg: BsColor.brandAzureLight)
                resolutionStatBadge(label: "已忽略", count: feedback.dismissed,
                                    fg: BsColor.inkMuted, bg: BsColor.inkMuted.opacity(0.15))
                resolutionStatBadge(label: "进行中", count: feedback.active,
                                    fg: BsColor.warning, bg: BsColor.warning.opacity(0.18))
                resolutionStatBadge(label: "待跟进", count: feedback.followUpRequired,
                                    fg: BsColor.warning, bg: BsColor.warning.opacity(0.18))
                resolutionStatBadge(label: "曾重开", count: feedback.reopenedCount,
                                    fg: .white, bg: BsColor.danger.opacity(0.85))
            }
        }
    }

    private func resolutionStatBadge(label: String, count: Int, fg: Color, bg: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(BsTypography.inter(13, weight: "SemiBold"))
            Text(label)
                .font(BsTypography.inter(11, weight: "Medium"))
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
                    .font(BsTypography.inter(12, weight: "SemiBold"))
                    .foregroundColor(tint)
            }
            if feedback.isProneToReopen {
                Text("易重开 · \(feedback.reopenedCount) 个曾重开的动作仍未完全解决。")
                    .font(BsTypography.inter(11, weight: "Regular"))
                    .foregroundColor(BsColor.warning)
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
                .foregroundColor(BsColor.inkMuted)
            Text("主要处理方式")
                .font(BsTypography.inter(11, weight: "Medium"))
                .foregroundColor(BsColor.inkMuted)
            Text(Self.humanize(category))
                .font(BsTypography.inter(12, weight: "SemiBold"))
                .foregroundColor(BsColor.ink)
        }
    }

    private func recentResolutionsList(resolutions: [ProjectResolutionFeedback.RecentResolution]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近治理动作")
                .font(BsTypography.inter(12, weight: "SemiBold"))
                .foregroundColor(BsColor.inkMuted)
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
                    .font(BsTypography.caption)
                    .foregroundColor(BsColor.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let effectiveness = resolution.effectiveness, !effectiveness.isEmpty {
                        effectivenessCapsule(effectiveness: effectiveness)
                    }
                    if let dateText = resolvedAtDisplayDate(resolution.resolvedAtRaw) {
                        Text(dateText)
                            .font(BsTypography.inter(11, weight: "Regular"))
                            .foregroundColor(BsColor.inkMuted)
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
            .font(BsTypography.inter(10, weight: "SemiBold"))
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
            if isLoading { return "加载中…" }
            if hasError { return "重试" }
            if hasResult || hasEmptyOrNoSource { return "刷新" }
            return "查看处理结果"
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
                        .font(BsTypography.inter(13, weight: "SemiBold"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(BsColor.brandAzure)
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
        case "resolved": return BsColor.success
        case "dismissed": return BsColor.inkMuted
        default: return BsColor.inkMuted
        }
    }

    /// Effectiveness capsule palette. Web's effectiveness vocabulary per migration 037:
    /// {effective, partial, ineffective, pending}. Unknown values render with a neutral
    /// tone so unexpected server expansion degrades gracefully (same posture as the rest
    /// of the 2.x defensive styling).
    // D.2a: Chinese labels matching Web's effectiveness palette.
    private static func effectivenessStyle(for raw: String) -> (String, Color, Color) {
        switch raw {
        case "effective":
            return ("有效", BsColor.brandAzure, BsColor.brandAzureLight)
        case "partial":
            return ("部分", BsColor.warning, BsColor.warning.opacity(0.18))
        case "ineffective":
            return ("无效", .white, BsColor.danger.opacity(0.85))
        case "pending":
            return ("待验证", BsColor.inkMuted, BsColor.inkMuted.opacity(0.15))
        default:
            return (humanize(raw), BsColor.inkMuted, BsColor.inkMuted.opacity(0.15))
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
            return ("干预已生效",
                    BsColor.brandAzure,
                    BsColor.brandAzureLight.opacity(0.55))
        case .needsIntervention:
            return ("待治理干预",
                    BsColor.warning,
                    BsColor.warning.opacity(0.18))
        case .none:
            return ("—",
                    BsColor.inkMuted,
                    BsColor.inkMuted.opacity(0.10))
        }
    }
}
