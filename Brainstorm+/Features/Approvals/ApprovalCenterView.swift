import SwiftUI
import Supabase

/// Sprint 4.3 — Approval module root. Replaces the direct
/// `ApprovalsListView` route (from 4.1) with a multi-tab shell:
///
///   - 我提交的 (mine) → `ApprovalsListView` + `MySubmissionsViewModel`
///   - 请假 / 外勤 / 出差 / 报销+采购 / 通用
///     → `ApprovalQueueView(kind:)` + `ApprovalQueueViewModel`
///
/// Sprint 4.4 — "+" toolbar button opens a type-picker sheet, which
/// routes to one of 4 submit forms (leave / reimbursement /
/// procurement / field_work). On successful submit we refresh the
/// "我提交的" list and switch to that tab — the user immediately sees
/// their new row.
///
/// Batch C.1 — 5 P1 parity items landed:
///   1. Capabilities gating: only render queue tabs the viewer can
///      actually act on (matches Web's `canApprove` +
///      `APPROVAL_TYPE_CAPABILITY_MAP`). Ordinary employees see only
///      `mine`.
///   2. Default tab: approvers land on their first visible pending
///      queue, non-approvers on `mine` (matches Web page.tsx:54).
///   3. Pending badges: red 99+-capped pill per queue tab, driven by
///      a head-only count query per visible kind on appear.
///
/// Parity target: Web `src/app/dashboard/approval/page.tsx`. Remaining
/// deltas (carried forward):
///   - AI assist audit list deferred.
///   - Web page renders badges with a framer-motion spring scale-in
///     on count change; iOS uses a plain `.contentTransition(.numericText())`
///     + implicit Spring animation via `.animation(.spring, value:)` —
///     equivalent feel, Apple-native motion stack.
public struct ApprovalCenterView: View {

    // Top-level tab enum. `mine` is special-cased; the queue tabs
    // share a single case with the kind as associated value so we can
    // iterate cleanly in the pill bar.
    public enum Tab: Hashable, Identifiable {
        case mine
        case queue(ApprovalQueueKind)

        public var id: String {
            switch self {
            case .mine: return "mine"
            case .queue(let k): return "queue.\(k.rawValue)"
            }
        }

        public var displayLabel: String {
            switch self {
            case .mine: return "我提交的"
            case .queue(let k): return k.displayLabel
            }
        }
    }

    @Environment(SessionManager.self) private var sessionManager
    @State private var selectedTab: Tab = .mine
    @State private var showTypePicker: Bool = false
    @State private var pendingSubmitKind: ApprovalSubmitKind?
    @State private var pendingCounts: [ApprovalQueueKind: Int] = [:]
    @State private var didApplyInitialDefault: Bool = false
    /// Phase 24 — shared zoom namespace for row → detail push. Rows in
    /// `ApprovalsListView` / `ApprovalQueueView` call
    /// `matchedTransitionSource(id: row.id, in: zoomNamespace)`; the
    /// `.navigationDestination(for: UUID.self)` registered below uses
    /// the same id to drive `.navigationTransition(.zoom(…))`.
    @Namespace private var zoomNamespace
    private let client: SupabaseClient

    // Hoisted so submit-success handlers can call `listMySubmissions()`
    // directly. Previously this was instantiated inline inside
    // `tabContent` — that created a fresh VM every tab switch, which
    // meant we'd lose the just-submitted row's visibility on switch.
    @StateObject private var mineViewModel: MySubmissionsViewModel

    /// Phase 3 isEmbedded：从 Dashboard 卡片 / ActionItemHelper 进入时借用
    /// caller 的 NavigationStack，避免内外双层 NavStack 导致"返回要按两次"。
    /// Tab 入口（MainTabView）仍然 default false —— tab 自带 NavStack。
    public let isEmbedded: Bool

    public init(client: SupabaseClient = supabase, isEmbedded: Bool = false) {
        self.client = client
        self.isEmbedded = isEmbedded
        _mineViewModel = StateObject(wrappedValue: MySubmissionsViewModel(client: client))
    }

    // MARK: - Capability-filtered tab list

    /// Effective capabilities of the current viewer (role defaults +
    /// explicit assignments − excluded). Computed per-render so that
    /// a profile refresh in `SessionManager` re-evaluates the gate.
    private var effectiveCapabilities: [Capability] {
        RBACManager.shared.getEffectiveCapabilities(for: sessionManager.currentProfile)
    }

    /// Whether the viewer holds ANY of the 11 approval caps. Mirrors
    /// Web `hasAnyCapability(capabilities, ALL_APPROVAL_CAPABILITIES)`
    /// (page.tsx:51).
    private var canApprove: Bool {
        hasAnyApprovalCapability(effectiveCapabilities)
    }

    /// Visible queue kinds in pill-bar order. A queue is visible iff
    /// the viewer has ANY of its `requiredCapabilities`.
    private var visibleQueueKinds: [ApprovalQueueKind] {
        ApprovalQueueKind.allCases.filter { kind in
            hasAnyCapability(effectiveCapabilities, required: kind.requiredCapabilities)
        }
    }

    /// Full ordered list rendered by the pill bar: `mine` always
    /// leads; approver queues append only when the viewer holds the
    /// matching capability.
    private var visibleTabs: [Tab] {
        [.mine] + visibleQueueKinds.map { .queue($0) }
    }

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
            BsColor.pageBackground
                .ignoresSafeArea()
            // Bug-fix(审批中心视图奇怪): VStack 不带 alignment 时,若当前 tab
            // 内容 (空/loading) 高度收缩,pillBar 会被垂直居中,视觉上像"tab 栏
            // 往下掉"。钉顶 + tabContent 撑满,保证 pillBar 始终贴在 nav 下方。
            VStack(spacing: 0) {
                tabPillBar
                Divider().opacity(0.4)
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("审批中心")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Haptic.light()
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
        .navigationDestination(for: UUID.self) { id in
            ApprovalDetailView(requestId: id, client: client)
                .navigationTransition(.zoom(sourceID: id, in: zoomNamespace))
        }
        // Type picker → sets `pendingSubmitKind` on selection; that
        // drives the per-type sheet below via `.sheet(item:)`.
        // Using two separate sheets (rather than one with inner
        // switch) avoids a jarring same-sheet content swap.
        .sheet(isPresented: $showTypePicker) {
            ApprovalSubmitTypePickerSheet { kind in
                pendingSubmitKind = kind
            }
        }
        .sheet(item: $pendingSubmitKind) { kind in
            submitSheet(for: kind)
        }
        .task {
            // Default-tab parity: Web (page.tsx:54) lands approvers
            // on the first pending queue and non-approvers on
            // `mine`. We apply this once on first appearance — a
            // subsequent capability toggle shouldn't silently jump
            // the user off their current tab.
            if !didApplyInitialDefault {
                didApplyInitialDefault = true
                if canApprove, let firstQueue = visibleQueueKinds.first {
                    selectedTab = .queue(firstQueue)
                }
                await refreshAllPendingCounts()
            }
        }
        .refreshable {
            await refreshAllPendingCounts()
        }
    }

    // MARK: - Pill bar

    @ViewBuilder
    private var tabPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleTabs) { tab in
                    pillButton(tab)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func pillButton(_ tab: Tab) -> some View {
        let isSelected = tab == selectedTab
        Button {
            Haptic.selection()
            selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Text(tab.displayLabel)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))

                if case .queue(let kind) = tab,
                   let count = pendingCounts[kind], count > 0 {
                    pendingBadge(count: count, onDark: isSelected)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? BsColor.brandAzure : BsColor.ink)
            .glassEffect(
                isSelected
                    ? .regular.tint(BsColor.brandAzure.opacity(0.28)).interactive()
                    : .regular.interactive(),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .animation(BsMotion.Anim.overshoot, value: pendingCounts)
    }

    /// Red 99+-capped badge. Mirrors Web page.tsx:147-158 — min-width
    /// 18pt circle, white bold text, shadowing ring. We use
    /// `.contentTransition(.numericText())` so count changes animate
    /// as tick-ups rather than abrupt swaps, closest native analog to
    /// Web's framer-motion spring scale-in on `key={count}`.
    @ViewBuilder
    private func pendingBadge(count: Int, onDark: Bool) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .glassEffect(.regular.tint(BsColor.danger.opacity(0.85)), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        onDark ? Color.white.opacity(0.75) : Color(.systemBackground),
                        lineWidth: 1.5
                    )
            )
            .accessibilityLabel("\(count) 条待审批")
    }

    // MARK: - Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .mine:
            // Uses the hoisted `mineViewModel` so submit-success
            // handlers can refresh it without depending on `.task`
            // re-firing. ApprovalsListView's own
            // `.navigationDestination(for: UUID.self)` would compete
            // with the one registered on this stack; the nearest
            // registration wins, and both produce the same detail
            // view, so the behavior is identical either way.
            ApprovalsListView(
                viewModel: mineViewModel,
                client: client,
                zoomNamespace: zoomNamespace
            )
        case .queue(let kind):
            // Keying the view identity on `kind` means switching tabs
            // creates a fresh `ApprovalQueueViewModel` each time
            // (lazy load on first view; the refreshable gesture lets
            // the user reload without leaving the tab). After the
            // queue VM's load settles, we refresh this queue's
            // pending badge so the header stays truthy.
            ApprovalQueueView(kind: kind, client: client, zoomNamespace: zoomNamespace)
                .id(kind.rawValue)
                .task(id: kind.rawValue) {
                    pendingCounts[kind] = await ApprovalQueueViewModel
                        .fetchPendingCount(kind: kind, client: client)
                }
        }
    }

    // MARK: - Submit sheets

    @ViewBuilder
    private func submitSheet(for kind: ApprovalSubmitKind) -> some View {
        switch kind {
        case .leave:
            LeaveSubmitView(client: client) { _ in
                handleSubmitted()
            }
        case .reimbursement:
            ReimbursementSubmitView(client: client) { _ in
                handleSubmitted()
            }
        case .procurement:
            ProcurementSubmitView(client: client) { _ in
                handleSubmitted()
            }
        case .fieldWork:
            FieldWorkSubmitView(client: client) { _ in
                handleSubmitted()
            }
        case .businessTrip:
            // Batch B.3 — direct-insert submit, no RPC. Parent still
            // dispatches to `handleSubmitted` so the "我提交的" tab
            // gets refreshed; however note that business_trip_requests
            // rows don't land in `approval_requests`, so the mine list
            // won't surface them unless it's extended to join this
            // table. That's an existing limitation — the approver
            // queue tab already shows them via ApprovalQueueKind.businessTrip.
            BusinessTripSubmitView(client: client) { _ in
                handleSubmitted()
            }
        }
    }

    /// Called from each submit form's `onSubmitted` callback. Switches
    /// to the "我提交的" tab and reloads the list so the user sees
    /// their new row at the top (rows are ordered `created_at DESC`).
    private func handleSubmitted() {
        selectedTab = .mine
        Task {
            await mineViewModel.listMySubmissions()
            // Refresh badges too — the submitter may also be an
            // approver of the same type, in which case the new row
            // lands in their own queue via a parallel code path.
            await refreshAllPendingCounts()
        }
    }

    // MARK: - Badge refresh

    /// Runs N parallel head-count queries (one per visible queue) in
    /// a TaskGroup. 5 queries is cheap enough to not need batching —
    /// the alternative (a single `GROUP BY request_type` count) would
    /// require a dedicated RPC because PostgREST only returns the
    /// GROUP keys via `.select("request_type, count:id")` which isn't
    /// exact-count-aware; sticking to parallel HEADs for now.
    private func refreshAllPendingCounts() async {
        let kinds = visibleQueueKinds
        guard !kinds.isEmpty else { return }

        await withTaskGroup(of: (ApprovalQueueKind, Int).self) { group in
            for kind in kinds {
                group.addTask {
                    let n = await ApprovalQueueViewModel.fetchPendingCount(
                        kind: kind,
                        client: client
                    )
                    return (kind, n)
                }
            }
            for await (kind, n) in group {
                await MainActor.run {
                    pendingCounts[kind] = n
                }
            }
        }
    }
}

#Preview {
    ApprovalCenterView(client: supabase)
        .environment(SessionManager())
}
