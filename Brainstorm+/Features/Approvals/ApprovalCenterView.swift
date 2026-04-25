import SwiftUI
import UIKit
import Supabase

/// Sprint 4.5 — 审批中心 redesigned root.
///
/// Replaces the prior pill-bar shell that delegated to `ApprovalsListView`
/// (mine) + `ApprovalQueueView` (queue) per-tab. The redesign collapses
/// the two child views into a single body owned by this file, backed by
/// `UnifiedApprovalCenterViewModel`. Motivations carried in the redesign
/// thread:
///
///   1. Tab-entry blank: previous shell raced with `LazyView` —
///      `selectedTab` was set in `.task {}` AFTER first body render, and
///      the queue child's `@StateObject` got initialized with no load
///      trigger reaching it before SwiftUI considered the body stable.
///      The unified VM here owns its own load lifecycle keyed on the
///      currently visible (mode, kind) pair, so the body is the single
///      source of truth for "what should be on screen right now".
///   2. Duplicate category modules: the old `mine` body had its own chip
///      filter row (`ApprovalsListView.typeFilterChipRow`) on top of this
///      file's pill bar. Users saw two filter strips. The redesign has
///      ONE chip scroller below a segmented mode switch.
///   3. Web-feel refresh: replaced the in-tab spinner overlay with
///      skeleton rows + native `.refreshable`. `refreshIfStale` debounces
///      `.onAppear` so re-entering the tab no longer flashes a spinner.
///
/// Visual reference: Apple Reminders + Files — tall page title, segmented
/// section divider, horizontal chip scroller, vertical sectioned list.
public struct ApprovalCenterView: View {

    // MARK: - State

    @Environment(SessionManager.self) private var sessionManager
    @StateObject private var viewModel: UnifiedApprovalCenterViewModel

    @State private var mode: UnifiedApprovalCenterViewModel.Mode = .queue
    @State private var selectedQueueKind: ApprovalQueueKind?
    /// Mine mode's local request-type filter — `nil` = 全部.
    @State private var selectedMineType: ApprovalRequestType?
    @State private var didApplyInitialDefault = false
    @State private var showTypePicker = false
    @State private var pendingSubmitKind: ApprovalSubmitKind?
    @State private var pendingAction: PendingAction?
    @Namespace private var zoomNamespace

    /// Long-press v3:申请人头像长按 → 弹 UserPreviewSheet。
    @State private var profilePreview: UserPreviewData? = nil

    private let client: SupabaseClient
    public let isEmbedded: Bool

    private struct PendingAction: Identifiable {
        let id = UUID()
        let row: ApprovalListRow
        let kind: ApprovalQueueKind
        let decision: ApprovalActionDecision
    }

    public init(client: SupabaseClient = supabase, isEmbedded: Bool = false) {
        self.client = client
        self.isEmbedded = isEmbedded
        _viewModel = StateObject(wrappedValue: UnifiedApprovalCenterViewModel(client: client))
    }

    // MARK: - Capability gating

    private var effectiveCapabilities: [Capability] {
        RBACManager.shared.getEffectiveCapabilities(for: sessionManager.currentProfile)
    }

    private var canApprove: Bool {
        hasAnyApprovalCapability(effectiveCapabilities)
    }

    private var visibleQueueKinds: [ApprovalQueueKind] {
        ApprovalQueueKind.allCases.filter { kind in
            hasAnyCapability(effectiveCapabilities, required: kind.requiredCapabilities)
        }
    }

    /// Order for mine mode chips (nil = 全部).
    private static let mineTypeChipOrder: [ApprovalRequestType?] = [
        nil,
        .leave,
        .businessTrip,
        .reimbursement,
        .procurement,
        .fieldWork,
        .generic,
    ]

    // MARK: - Body

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    @ViewBuilder
    private var coreContent: some View {
        ZStack {
            BsColor.pageBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. Mode segmented control + 2. chip scroller live in a
                //    sticky header — they don't scroll with the list.
                headerSection
                Divider().opacity(0.4)
                bodySection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("审批中心")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { newSubmissionButton }
        .navigationDestination(for: UUID.self) { id in
            ApprovalDetailView(requestId: id, client: client)
                .navigationTransition(.zoom(sourceID: id, in: zoomNamespace))
        }
        .sheet(isPresented: $showTypePicker) {
            ApprovalSubmitTypePickerSheet { kind in
                pendingSubmitKind = kind
            }
        }
        .sheet(item: $pendingSubmitKind) { kind in
            submitSheet(for: kind)
        }
        .sheet(item: $pendingAction) { action in
            commentSheet(for: action)
        }
        .sheet(item: $profilePreview) { user in
            UserPreviewSheet(user: user)
        }
        .zyErrorBanner($viewModel.errorMessage)
        .refreshable {
            await refresh(force: true)
        }
        .task {
            await applyInitialDefaultsIfNeeded()
        }
        .onAppear {
            // Re-entering the tab — refreshIfStale (60s TTL) avoids
            // spinner-flashing for the user; foreground refresh still
            // fires when the cache has gone stale.
            Task { await refreshIfStale() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: BsSpacing.sm) {
            modeSegmentedControl
                .padding(.horizontal, BsSpacing.lg)
                .padding(.top, BsSpacing.sm)

            chipScroller
                .padding(.bottom, BsSpacing.sm)
        }
    }

    @ViewBuilder
    private var modeSegmentedControl: some View {
        // Native picker style — Apple Mail's "All / Unread" pattern.
        // Driving via Picker (vs hand-rolled buttons) lets iOS handle
        // tint + selection ring transitions for free.
        Picker("视图", selection: $mode) {
            Text(UnifiedApprovalCenterViewModel.Mode.queue.label).tag(UnifiedApprovalCenterViewModel.Mode.queue)
            Text(UnifiedApprovalCenterViewModel.Mode.mine.label).tag(UnifiedApprovalCenterViewModel.Mode.mine)
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _, newMode in
            Haptic.selection()
            // Switching mode — fire a refresh for whatever (mode, kind)
            // we're now showing. refreshIfStale honors cache.
            Task { await refreshIfStale() }
        }
    }

    @ViewBuilder
    private var chipScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BsSpacing.xs + 2) {
                switch mode {
                case .queue:
                    if visibleQueueKinds.isEmpty {
                        // No approval caps → no queue chips. The empty
                        // state below will tell the user to switch tabs.
                        chip(label: "无审批权限", count: nil, isSelected: false, isDisabled: true) {}
                    } else {
                        ForEach(visibleQueueKinds, id: \.self) { kind in
                            chip(
                                label: kind.displayLabel,
                                count: pendingCount(for: kind),
                                isSelected: selectedQueueKind == kind,
                                isDisabled: false
                            ) {
                                Haptic.selection()
                                selectedQueueKind = kind
                                Task { await refreshIfStale() }
                            }
                        }
                    }
                case .mine:
                    ForEach(Self.mineTypeChipOrder, id: \.self) { type in
                        chip(
                            label: type?.displayLabel ?? "全部",
                            count: countForMine(type),
                            isSelected: selectedMineType == type,
                            isDisabled: false
                        ) {
                            Haptic.selection()
                            selectedMineType = type
                        }
                    }
                }
            }
            .padding(.horizontal, BsSpacing.lg)
        }
    }

    /// 2026-04-25 — chip 升级为 iOS 26 原生 Liquid Glass:
    ///   • 高度 ≥ 44pt(Apple HIG 触控目标),水平 padding 16pt,字号 14pt
    ///   • 选中态用 `.glassEffect(.regular.tint(BsColor.brandAzure)
    ///     .interactive(), in: Capsule())`,与项目其他 glass 标签一致
    ///     (TeamAttendanceView / ApprovalQueueView)
    ///   • 未选中也走 `.glassEffect(.regular.interactive(), in: Capsule())`
    ///     提供 Liquid Glass 的折射感,而不是干瘪的纯色 capsule
    ///   • 禁用态走 plain capsule,避免 glass 闪烁误导
    @ViewBuilder
    private func chip(
        label: String,
        count: Int?,
        isSelected: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? Color.white.opacity(0.95) : BsColor.inkFaint
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                isSelected
                                ? Color.white.opacity(0.22)
                                : BsColor.inkFaint.opacity(0.12)
                            )
                        )
                }
            }
            .padding(.horizontal, BsSpacing.md + 4)  // 16pt
            .frame(minHeight: 44)
            .foregroundStyle(
                isDisabled ? BsColor.inkFaint
                : (isSelected ? Color.white : BsColor.ink)
            )
            .modifier(ChipGlassBackground(isSelected: isSelected, isDisabled: isDisabled))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var newSubmissionButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showTypePicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(BsColor.brandAzure)
                    .frame(width: 32, height: 32)
                    .glassEffect(.regular.tint(BsColor.brandAzure.opacity(0.18)).interactive(), in: Circle())
            }
            .accessibilityLabel("新建审批")
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var bodySection: some View {
        switch mode {
        case .queue:
            queueBody
        case .mine:
            mineBody
        }
    }

    // MARK: - Queue body

    @ViewBuilder
    private var queueBody: some View {
        if let kind = selectedQueueKind {
            let rows = viewModel.queueRowsByKind[kind] ?? []
            if viewModel.isLoading && rows.isEmpty {
                skeletonList
            } else if rows.isEmpty {
                queueEmptyState(kind)
            } else {
                queueSectionedList(rows: rows, kind: kind)
            }
        } else {
            // No approval caps — nothing to show in queue mode.
            BsEmptyState(
                title: "暂无审批权限",
                systemImage: "lock.shield",
                description: "切换到「我提」查看你提交的审批,或联系管理员授予审批权限。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func queueEmptyState(_ kind: ApprovalQueueKind) -> some View {
        ContentUnavailableView(
            "暂无\(kind.displayLabel)审批",
            systemImage: "checkmark.seal",
            description: Text("队列已清空。下拉可刷新。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func queueSectionedList(rows: [ApprovalListRow], kind: ApprovalQueueKind) -> some View {
        // Group by status into 3 buckets — pending first, then approved,
        // then rejected. Other statuses (withdrawn / cancelled) fall into
        // a 4th "其他" bucket so we never silently drop a row.
        let pending = rows.filter { $0.status == .pending }
        let approved = rows.filter { $0.status == .approved }
        let rejected = rows.filter { $0.status == .rejected }
        let other = rows.filter {
            ![.pending, .approved, .rejected].contains($0.status)
        }

        List {
            if !pending.isEmpty {
                section(title: "待我审批", count: pending.count) {
                    ForEach(Array(pending.enumerated()), id: \.element.id) { index, row in
                        queueRow(row, kind: kind, index: index)
                    }
                }
            }
            if !approved.isEmpty {
                section(title: "已通过", count: approved.count) {
                    ForEach(Array(approved.enumerated()), id: \.element.id) { index, row in
                        queueRow(row, kind: kind, index: index)
                    }
                }
            }
            if !rejected.isEmpty {
                section(title: "已拒绝", count: rejected.count) {
                    ForEach(Array(rejected.enumerated()), id: \.element.id) { index, row in
                        queueRow(row, kind: kind, index: index)
                    }
                }
            }
            if !other.isEmpty {
                section(title: "其他", count: other.count) {
                    ForEach(Array(other.enumerated()), id: \.element.id) { index, row in
                        queueRow(row, kind: kind, index: index)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private func queueRow(_ row: ApprovalListRow, kind: ApprovalQueueKind, index: Int) -> some View {
        NavigationLink(value: row.id) {
            QueueRowView(row: row, onAvatarLongPress: {
                profilePreview = makePreview(from: row.requesterProfile)
            })
                .matchedTransitionSource(id: row.id, in: zoomNamespace)
        }
        .bsAppearStagger(index: index)
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(
            top: BsSpacing.xs,
            leading: BsSpacing.lg,
            bottom: BsSpacing.xs,
            trailing: BsSpacing.lg
        ))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if row.status == .pending && kind.supportsWriteOnIOS {
                Button {
                    Haptic.warning()
                    pendingAction = PendingAction(row: row, kind: kind, decision: .reject)
                } label: {
                    Label("拒绝", systemImage: "xmark.circle")
                }
                .tint(BsColor.danger)

                Button {
                    Haptic.success()
                    pendingAction = PendingAction(row: row, kind: kind, decision: .approve)
                } label: {
                    Label("批准", systemImage: "checkmark.circle")
                }
                .tint(BsColor.success)
            }
        }
        .contextMenu {
            NavigationLink(value: row.id) {
                Label("查看详情", systemImage: "arrow.up.forward.square")
            }
            if row.status == .pending && kind.supportsWriteOnIOS {
                Button {
                    Haptic.success()
                    pendingAction = PendingAction(row: row, kind: kind, decision: .approve)
                } label: {
                    Label("批准", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    Haptic.warning()
                    pendingAction = PendingAction(row: row, kind: kind, decision: .reject)
                } label: {
                    Label("拒绝", systemImage: "xmark.circle")
                }
            }
            if let name = row.requesterProfile?.fullName, !name.isEmpty {
                Button {
                    UIPasteboard.general.string = name
                    Haptic.light()
                } label: {
                    Label("复制申请人", systemImage: "person")
                }
            }
        }
    }

    // MARK: - Mine body

    @ViewBuilder
    private var mineBody: some View {
        let filtered: [ApprovalMySubmissionRow] = {
            guard let f = selectedMineType else { return viewModel.mineRows }
            return viewModel.mineRows.filter { $0.requestType == f }
        }()

        if viewModel.isLoading && viewModel.mineRows.isEmpty {
            skeletonList
        } else if filtered.isEmpty {
            BsEmptyState(
                title: selectedMineType == nil ? "暂无提交记录" : "暂无\(selectedMineType!.displayLabel)记录",
                systemImage: "tray",
                description: selectedMineType == nil
                    ? "你还没有提交过审批申请。点击右上角「+」新建一条。"
                    : "切换到「全部」查看其他类型,或新建一条。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            mineSectionedList(rows: filtered)
        }
    }

    @ViewBuilder
    private func mineSectionedList(rows: [ApprovalMySubmissionRow]) -> some View {
        let pending = rows.filter { $0.status == .pending }
        let approved = rows.filter { $0.status == .approved }
        let rejected = rows.filter { $0.status == .rejected }
        let other = rows.filter {
            ![.pending, .approved, .rejected].contains($0.status)
        }

        List {
            if !pending.isEmpty {
                section(title: "审批中", count: pending.count) {
                    ForEach(Array(pending.enumerated()), id: \.element.id) { index, row in
                        mineRow(row, index: index)
                    }
                }
            }
            if !approved.isEmpty {
                section(title: "已通过", count: approved.count) {
                    ForEach(Array(approved.enumerated()), id: \.element.id) { index, row in
                        mineRow(row, index: index)
                    }
                }
            }
            if !rejected.isEmpty {
                section(title: "已拒绝", count: rejected.count) {
                    ForEach(Array(rejected.enumerated()), id: \.element.id) { index, row in
                        mineRow(row, index: index)
                    }
                }
            }
            if !other.isEmpty {
                section(title: "其他", count: other.count) {
                    ForEach(Array(other.enumerated()), id: \.element.id) { index, row in
                        mineRow(row, index: index)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private func mineRow(_ row: ApprovalMySubmissionRow, index: Int) -> some View {
        NavigationLink(value: row.id) {
            MineRowView(row: row)
                .matchedTransitionSource(id: row.id, in: zoomNamespace)
        }
        .bsAppearStagger(index: index)
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(
            top: BsSpacing.xs,
            leading: BsSpacing.lg,
            bottom: BsSpacing.xs,
            trailing: BsSpacing.lg
        ))
        // Swipe-actions system (docs/swipe-actions-system.md):"我提交的"行
        // 没有 destructive 选项（撤回 RPC 待实现 —— 仅 chat / 任务有
        // 可逆 destructive）。leading swipe 提供"复制编号"高频用法。
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                UIPasteboard.general.string = row.id.uuidString
                Haptic.light()
            } label: {
                Label("复制编号", systemImage: "doc.on.doc")
            }
            .tint(BsColor.brandAzure)
        }
        .contextMenu {
            NavigationLink(value: row.id) {
                Label("查看详情", systemImage: "arrow.up.forward.square")
            }
            Button {
                UIPasteboard.general.string = row.id.uuidString
                Haptic.light()
            } label: {
                Label("复制编号", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: - Section header helper

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            HStack(spacing: 6) {
                Text(title)
                    .font(BsTypography.meta)
                    .kerning(0.8)
                    .foregroundStyle(BsColor.inkMuted)
                Text("\(count)")
                    .font(BsTypography.meta)
                    .foregroundStyle(BsColor.inkFaint)
                Spacer(minLength: 0)
            }
            .textCase(nil)
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.xs)
            .listRowInsets(EdgeInsets())
            .background(Color.clear)
        }
    }

    // MARK: - Skeleton

    @ViewBuilder
    private var skeletonList: some View {
        VStack(spacing: BsSpacing.sm) {
            ForEach(0..<4, id: \.self) { _ in
                BsContentCard(padding: .none) {
                    VStack(alignment: .leading, spacing: BsSpacing.sm) {
                        HStack(spacing: BsSpacing.md) {
                            Circle()
                                .fill(BsColor.inkFaint.opacity(0.25))
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: BsRadius.xs)
                                    .fill(BsColor.inkFaint.opacity(0.3))
                                    .frame(width: 140, height: 12)
                                RoundedRectangle(cornerRadius: BsRadius.xs)
                                    .fill(BsColor.inkFaint.opacity(0.2))
                                    .frame(width: 80, height: 10)
                            }
                            Spacer(minLength: 0)
                        }
                        RoundedRectangle(cornerRadius: BsRadius.xs)
                            .fill(BsColor.inkFaint.opacity(0.18))
                            .frame(height: 10)
                            .padding(.top, 4)
                    }
                    .padding(BsSpacing.md)
                }
            }
        }
        .padding(.horizontal, BsSpacing.lg)
        .padding(.top, BsSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .redacted(reason: .placeholder)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func submitSheet(for kind: ApprovalSubmitKind) -> some View {
        switch kind {
        case .leave:
            LeaveSubmitView(client: client) { _ in handleSubmitted() }
        case .reimbursement:
            ReimbursementSubmitView(client: client) { _ in handleSubmitted() }
        case .procurement:
            ProcurementSubmitView(client: client) { _ in handleSubmitted() }
        case .fieldWork:
            FieldWorkSubmitView(client: client) { _ in handleSubmitted() }
        case .businessTrip:
            BusinessTripSubmitView(client: client) { _ in handleSubmitted() }
        }
    }

    @ViewBuilder
    private func commentSheet(for action: PendingAction) -> some View {
        ApprovalCommentSheet(
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            decision: action.decision,
            requestLabel: Self.sheetLabel(for: action.row)
        ) { comment in
            await viewModel.applyAction(
                on: action.row,
                kind: action.kind,
                decision: action.decision,
                comment: comment
            )
        }
    }

    private static func sheetLabel(for row: ApprovalListRow) -> String {
        let typeLabel = row.requestType.displayLabel
        let name = row.requesterProfile?.fullName ?? "未知用户"
        return "\(typeLabel) · \(name)"
    }

    /// Long-press v3:把申请人 ApprovalActorProfile 提为 UserPreviewSheet
    /// 能消化的 UserPreviewData。ApprovalActorProfile.id 是 UUID? —— 没 id
    /// 时返回 nil(sheet 不弹),避免 UserPreviewSheet 拿到无效 id。
    private func makePreview(from actor: ApprovalActorProfile?) -> UserPreviewData? {
        guard let actor, let id = actor.id else { return nil }
        return UserPreviewData(
            id: id,
            fullName: actor.fullName,
            avatarUrl: actor.avatarUrl,
            department: actor.department
        )
    }

    // MARK: - Lifecycle

    private func applyInitialDefaultsIfNeeded() async {
        guard !didApplyInitialDefault else {
            await refreshIfStale()
            return
        }
        didApplyInitialDefault = true

        // Default mode: approver lands on `.queue` with first available
        // kind selected; non-approver lands on `.mine`.
        if canApprove, let firstKind = visibleQueueKinds.first {
            mode = .queue
            selectedQueueKind = firstKind
        } else {
            mode = .mine
            selectedQueueKind = nil
        }

        // Always seed pending counts so chips show badges from the start.
        await viewModel.refreshPendingCounts(for: visibleQueueKinds)
        await refresh(force: true)
    }

    private func refresh(force: Bool) async {
        switch mode {
        case .queue:
            if let kind = selectedQueueKind {
                if force {
                    await viewModel.refresh(mode: .queue, kind: kind)
                } else {
                    await viewModel.refreshIfStale(mode: .queue, kind: kind)
                }
            }
            await viewModel.refreshPendingCounts(for: visibleQueueKinds)
        case .mine:
            if force {
                await viewModel.refresh(mode: .mine, kind: nil)
            } else {
                await viewModel.refreshIfStale(mode: .mine, kind: nil)
            }
        }
    }

    private func refreshIfStale() async {
        await refresh(force: false)
    }

    private func handleSubmitted() {
        // Newly-submitted rows are the user's own — switch to mine mode
        // so they immediately see the new row at top of "审批中".
        mode = .mine
        selectedMineType = nil
        Task {
            await viewModel.refresh(mode: .mine, kind: nil)
            await viewModel.refreshPendingCounts(for: visibleQueueKinds)
        }
    }

    // MARK: - Helpers

    private func pendingCount(for kind: ApprovalQueueKind) -> Int? {
        let n = viewModel.pendingCounts[kind] ?? 0
        return n > 0 ? n : nil
    }

    private func countForMine(_ type: ApprovalRequestType?) -> Int? {
        guard let type else {
            let n = viewModel.mineRows.count
            return n > 0 ? n : nil
        }
        let n = viewModel.mineRows.filter { $0.requestType == type }.count
        return n > 0 ? n : nil
    }
}

// ══════════════════════════════════════════════════════════════════
// MARK: - Row views
// ══════════════════════════════════════════════════════════════════

/// Queue row — shown in 我审 mode. Apple-Mail-density: 36pt avatar +
/// name + meta line + status chip on the right. Tap pushes detail.
///
/// Long-press v3: avatar 长按 → 触发 onAvatarLongPress(申请人 profile)
/// 走外层 UserPreviewSheet。caller 用 PreviewRequest 装 ApprovalActorProfile
/// → UserPreviewData 转换。
private struct QueueRowView: View {
    let row: ApprovalListRow
    var onAvatarLongPress: (() -> Void)? = nil

    var body: some View {
        BsContentCard(padding: .none) {
            HStack(alignment: .top, spacing: BsSpacing.md) {
                avatar
                    .contextMenu {
                        if onAvatarLongPress != nil {
                            Button {
                                onAvatarLongPress?()
                            } label: {
                                Label("查看资料", systemImage: "person.crop.square.filled.and.at.rectangle")
                            }
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.requesterProfile?.fullName ?? "未知用户")
                            .font(BsTypography.cardSubtitle)
                            .foregroundStyle(BsColor.ink)
                            .lineLimit(1)

                        typeChip
                        prioritychipIfAny
                        Spacer(minLength: 0)
                        statusChip
                    }

                    if row.startDate != nil || row.endDate != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundStyle(BsColor.inkFaint)
                            Text(leaveSpanText)
                                .font(BsTypography.caption)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                    }

                    if let reason = row.businessReason, !reason.isEmpty {
                        Text(reason)
                            .font(BsTypography.caption)
                            .foregroundStyle(BsColor.inkMuted)
                            .lineLimit(2)
                    }

                    Text(Self.dateFormatter.string(from: row.createdAt))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkFaint)
                        .padding(.top, 2)
                }
            }
            .padding(BsSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.12))
                .frame(width: 36, height: 36)
            Text(row.requesterProfile?.initial ?? "?")
                .font(BsTypography.cardSubtitle)
                .foregroundStyle(BsColor.brandAzure)
        }
    }

    @ViewBuilder
    private var typeChip: some View {
        Text(row.requestType.displayLabel)
            .font(BsTypography.captionSmall.weight(.semibold))
            .foregroundStyle(BsColor.brandAzure)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.xs, style: .continuous)
                    .fill(BsColor.brandAzure.opacity(0.12))
            )
    }

    @ViewBuilder
    private var prioritychipIfAny: some View {
        if row.priorityByRequester == .high || row.priorityByRequester == .urgent {
            let tint: Color = row.priorityByRequester == .urgent ? BsColor.danger : BsColor.warning
            let label: String = row.priorityByRequester == .urgent ? "紧急" : "高"
            Text(label)
                .font(BsTypography.captionSmall.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: BsRadius.xs, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        let tone = row.status.tone
        Text(row.status.displayLabel)
            .font(BsTypography.captionSmall.weight(.medium))
            .foregroundStyle(toneForeground(tone))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.full, style: .continuous)
                    .fill(toneBackground(tone))
            )
    }

    private func toneBackground(_ tone: ApprovalStatus.Tone) -> Color {
        switch tone {
        case .warning: return BsColor.warning.opacity(0.15)
        case .success: return BsColor.success.opacity(0.15)
        case .danger:  return BsColor.danger.opacity(0.15)
        case .info:    return BsColor.brandAzure.opacity(0.15)
        case .neutral: return BsColor.inkMuted.opacity(0.18)
        }
    }

    private func toneForeground(_ tone: ApprovalStatus.Tone) -> Color {
        switch tone {
        case .warning: return BsColor.warning
        case .success: return BsColor.success
        case .danger:  return BsColor.danger
        case .info:    return BsColor.brandAzure
        case .neutral: return BsColor.inkMuted
        }
    }

    private var leaveSpanText: String {
        var parts: [String] = []
        if let start = row.startDate, let end = row.endDate, start != end {
            parts.append("\(start) → \(end)")
        } else if let only = row.startDate ?? row.endDate {
            parts.append(only)
        }
        if let days = row.days {
            parts.append(String(format: "%g 天", days))
        }
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

/// Mine row — shown in 我提 mode. Slimmer than the queue row (no
/// requester avatar — it's always you), focuses on type + status +
/// timing.
private struct MineRowView: View {
    let row: ApprovalMySubmissionRow

    var body: some View {
        BsContentCard(padding: .none) {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                HStack(spacing: BsSpacing.sm) {
                    Text(row.requestType.displayLabel)
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)
                    statusChip
                    Spacer(minLength: 0)
                    Text(Self.dateFormatter.string(from: row.createdAt))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkFaint)
                }

                if row.requestType == .leave, let leave = row.leave {
                    Text(leavePreviewText(leave))
                        .font(BsTypography.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }

                if let reason = row.businessReason, !reason.isEmpty {
                    Text(reason)
                        .font(BsTypography.caption)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(2)
                }

                if let note = row.reviewerNote, !note.isEmpty {
                    HStack(alignment: .top, spacing: BsSpacing.sm) {
                        Rectangle()
                            .fill(BsColor.borderSubtle)
                            .frame(width: 2)
                        Text("审批意见：\(note)")
                            .font(BsTypography.caption)
                            .foregroundStyle(BsColor.inkMuted)
                            .lineLimit(3)
                    }
                }
            }
            .padding(BsSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        let tone = row.status.tone
        Text(row.status.displayLabel)
            .font(BsTypography.captionSmall.weight(.medium))
            .foregroundStyle(toneForeground(tone))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.full, style: .continuous)
                    .fill(toneBackground(tone))
            )
    }

    private func toneBackground(_ tone: ApprovalStatus.Tone) -> Color {
        switch tone {
        case .warning: return BsColor.warning.opacity(0.15)
        case .success: return BsColor.success.opacity(0.15)
        case .danger:  return BsColor.danger.opacity(0.15)
        case .info:    return BsColor.brandAzure.opacity(0.15)
        case .neutral: return BsColor.inkMuted.opacity(0.18)
        }
    }

    private func toneForeground(_ tone: ApprovalStatus.Tone) -> Color {
        switch tone {
        case .warning: return BsColor.warning
        case .success: return BsColor.success
        case .danger:  return BsColor.danger
        case .info:    return BsColor.brandAzure
        case .neutral: return BsColor.inkMuted
        }
    }

    private func leavePreviewText(_ leave: ApprovalLeaveDetail) -> String {
        var parts: [String] = []
        if leave.leaveType != .unknown {
            parts.append(leave.leaveType.displayLabel)
        }
        parts.append("\(leave.startDate) ~ \(leave.endDate)")
        parts.append(String(format: "%g 天", leave.days))
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

// ══════════════════════════════════════════════════════════════════
// MARK: - Chip glass background
// ══════════════════════════════════════════════════════════════════

/// iOS 26 Liquid Glass capsule for ApprovalCenterView 的分类 chip。
///
/// 选中态走 `.glassEffect(.regular.tint(BsColor.brandAzure).interactive(),
/// in: Capsule())` —— 与 TeamAttendanceView / ApprovalQueueView 的玻璃标签
/// 同款,品牌蓝玻璃。未选中走纯 `.glassEffect(.regular.interactive(),
/// in: Capsule())`,保留 Liquid Glass 的折射 + 触控反馈但不染色。禁用态
/// 走静态半透明 capsule,避免在"无审批权限"占位时玻璃闪烁。
private struct ChipGlassBackground: ViewModifier {
    let isSelected: Bool
    let isDisabled: Bool

    func body(content: Content) -> some View {
        if isDisabled {
            content.background(
                Capsule().fill(BsColor.inkFaint.opacity(0.10))
            )
        } else if isSelected {
            content.glassEffect(
                .regular.tint(BsColor.brandAzure).interactive(),
                in: Capsule()
            )
        } else {
            content.glassEffect(
                .regular.interactive(),
                in: Capsule()
            )
        }
    }
}

#Preview {
    ApprovalCenterView(client: supabase)
        .environment(SessionManager())
}
