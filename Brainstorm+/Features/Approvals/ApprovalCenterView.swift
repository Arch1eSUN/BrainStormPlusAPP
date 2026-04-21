import SwiftUI
import Supabase

/// Sprint 4.3 — Approval module root. Replaces the direct
/// `ApprovalsListView` route (from 4.1) with a 7-tab shell:
///
///   - 我提交的 (mine) → `ApprovalsListView` + `MySubmissionsViewModel`
///   - 请假 / 外勤 / 出差 / 报销/采购 / 日报/周报 / 通用
///     → `ApprovalQueueView(kind:)` + `ApprovalQueueViewModel`
///
/// Sprint 4.4 — "+" toolbar button opens a type-picker sheet, which
/// routes to one of 4 submit forms (leave / reimbursement /
/// procurement / field_work). On successful submit we refresh the
/// "我提交的" list and switch to that tab — the user immediately sees
/// their new row.
///
/// Parity target: Web `src/app/dashboard/approval/page.tsx`. Deltas:
///
///   - Web hides approver tabs when
///     `!hasAnyCapability(capabilities, ALL_APPROVAL_CAPABILITIES)`.
///     iOS does *not* do this gate client-side yet — RLS + the RPC
///     enforce the actual permission boundary on the server, so a
///     non-approver sees empty queues but can't act. A future polish
///     pass can fetch `profiles.capabilities` and hide the pills
///     they'll never see rows in; deferred to keep 4.3 scoped.
///   - Web lands approvers on the first pending queue, non-approvers
///     on `mine`. iOS starts on `mine` for everyone — simpler default,
///     and the pills are one tap away.
///   - Badge counts (pending per tab) are skipped this sprint. They
///     need either 6 parallel fetches on mount or a single
///     `GROUP BY request_type` count query. Revisit as a polish item.
///   - 4.4 adds only 4 submit types (the MVP set). Business trip,
///     daily/weekly log submission, generic, attendance exception are
///     all deferred — business trip is a separate domain model,
///     daily/weekly flow through a different pipeline, generic has no
///     server-side RPC yet.
///
/// Owning the `NavigationStack` here means both `ApprovalsListView`
/// and `ApprovalQueueView` can push `ApprovalDetailView` the same
/// way — both use value-based `NavigationLink(value: UUID)` with the
/// `.navigationDestination(for: UUID.self)` registered on this view.
public struct ApprovalCenterView: View {

    // Top-level tab enum. `mine` is special-cased; the 6 queue tabs
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

        /// The ordered list rendered by the pill bar.
        public static let all: [Tab] = {
            var items: [Tab] = [.mine]
            items.append(contentsOf: ApprovalQueueKind.allCases.map { .queue($0) })
            return items
        }()
    }

    @State private var selectedTab: Tab = .mine
    @State private var showTypePicker: Bool = false
    @State private var pendingSubmitKind: ApprovalSubmitKind?
    private let client: SupabaseClient

    // Hoisted so submit-success handlers can call `listMySubmissions()`
    // directly. Previously this was instantiated inline inside
    // `tabContent` — that created a fresh VM every tab switch, which
    // meant we'd lose the just-submitted row's visibility on switch.
    @StateObject private var mineViewModel: MySubmissionsViewModel

    public init(client: SupabaseClient = supabase) {
        self.client = client
        _mineViewModel = StateObject(wrappedValue: MySubmissionsViewModel(client: client))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPillBar
                Divider().opacity(0.4)
                tabContent
            }
            .navigationTitle("审批中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showTypePicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建审批")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ApprovalDetailView(requestId: id, client: client)
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
        }
    }

    // MARK: - Pill bar

    @ViewBuilder
    private var tabPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Tab.all) { tab in
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
            selectedTab = tab
        } label: {
            Text(tab.displayLabel)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(
                        isSelected ? Color.accentColor : Color(.secondarySystemBackground)
                    )
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
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
                client: client
            )
        case .queue(let kind):
            // Keying the view identity on `kind` means switching tabs
            // creates a fresh `ApprovalQueueViewModel` each time
            // (lazy load on first view; the refreshable gesture lets
            // the user reload without leaving the tab).
            ApprovalQueueView(kind: kind, client: client)
                .id(kind.rawValue)
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
        }
    }

    /// Called from each submit form's `onSubmitted` callback. Switches
    /// to the "我提交的" tab and reloads the list so the user sees
    /// their new row at the top (rows are ordered `created_at DESC`).
    private func handleSubmitted() {
        selectedTab = .mine
        Task {
            await mineViewModel.listMySubmissions()
        }
    }
}

#Preview {
    ApprovalCenterView(client: supabase)
}
