import SwiftUI
import Supabase

/// Sprint 4.3 — Approval module root. Replaces the direct
/// `ApprovalsListView` route (from 4.1) with a 7-tab shell:
///
///   - 我提交的 (mine) → `ApprovalsListView` + `MySubmissionsViewModel`
///   - 请假 / 外勤 / 出差 / 报销/采购 / 日报/周报 / 通用
///     → `ApprovalQueueView(kind:)` + `ApprovalQueueViewModel`
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
    private let client: SupabaseClient

    public init(client: SupabaseClient = supabase) {
        self.client = client
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
            .navigationDestination(for: UUID.self) { id in
                ApprovalDetailView(requestId: id, client: client)
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
            // Reuse 4.1's list. Its own `.navigationDestination(for: UUID.self)`
            // would compete with the one registered on this stack; we
            // consolidate deep linking here. That's why
            // `ApprovalsListView` wasn't wrapped in its own NavigationStack
            // in 4.1 (see ApprovalsListView.swift:49-51 where the destination
            // is still declared — the outer stack takes precedence, which is
            // fine because both registrations produce the same
            // `ApprovalDetailView` and SwiftUI resolves the nearest one).
            ApprovalsListView(
                viewModel: MySubmissionsViewModel(client: client),
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
}

#Preview {
    ApprovalCenterView(client: supabase)
}
