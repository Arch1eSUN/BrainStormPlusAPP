import SwiftUI
import Supabase

/// Sprint 4.3 — Approver queue screen.
///
/// Per-tab view used inside `ApprovalCenterView`. One instance per
/// `ApprovalQueueKind` — the `@StateObject` VM is re-created when the
/// user switches tabs (SwiftUI identity is keyed on `kind` upstream),
/// so each kind loads lazily on first view.
///
/// 1:1 port of Web `src/app/dashboard/approval/_tabs/<kind>-list.tsx`
/// with these deltas:
///   - We don't model tab-specific empty-state copy per tab; one
///     shared "暂无审批" is good enough for iOS (Web varies by tab but
///     the delta is purely cosmetic).
///   - Approve/reject writes go through the `approvals_apply_action`
///     RPC (migration 20260421170000) instead of Web's TS action.
///     Leave kind is read-only: the RPC rejects leave to avoid
///     desyncing comp_time quota / DWS via the Next.js hook layer.
///     We gate the buttons client-side on `kind.supportsWriteOnIOS`.
///
/// Rows navigate into `ApprovalDetailView` via value-based
/// `NavigationLink` — same pattern as `ApprovalsListView` (4.1).
/// The enclosing `NavigationStack` lives on `ApprovalCenterView`.
public struct ApprovalQueueView: View {
    @StateObject private var viewModel: ApprovalQueueViewModel
    private let client: SupabaseClient
    /// Phase 24 — zoom transition source namespace, shared with
    /// `ApprovalCenterView` so row → detail push animates as a zoom.
    /// Optional so previews / direct embeddings compile without one.
    private let zoomNamespace: Namespace.ID?

    /// When non-nil, the comment sheet is presented for the carried
    /// (row, decision) pair. Resetting to nil dismisses — we bind a
    /// computed `Bool` to the sheet's `isPresented` so the sheet itself
    /// can close by clearing this state.
    @State private var pendingAction: PendingAction?

    private struct PendingAction: Identifiable {
        let id = UUID()
        let row: ApprovalListRow
        let decision: ApprovalActionDecision
    }

    public init(
        kind: ApprovalQueueKind,
        client: SupabaseClient,
        zoomNamespace: Namespace.ID? = nil
    ) {
        _viewModel = StateObject(wrappedValue: ApprovalQueueViewModel(kind: kind, client: client))
        self.client = client
        self.zoomNamespace = zoomNamespace
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.rows.isEmpty {
                ContentUnavailableView(
                    "暂无审批",
                    systemImage: "checkmark.seal",
                    description: Text(emptyDescription)
                )
            } else {
                queueList
            }
        }
        .zyErrorBanner($viewModel.errorMessage)
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
        .sheet(item: $pendingAction) { action in
            ApprovalCommentSheet(
                isPresented: Binding(
                    get: { pendingAction != nil },
                    set: { if !$0 { pendingAction = nil } }
                ),
                decision: action.decision,
                requestLabel: Self.sheetLabel(for: action.row)
            ) { comment in
                await viewModel.applyAction(
                    to: action.row.id,
                    decision: action.decision,
                    comment: comment
                )
            }
        }
    }

    private static func sheetLabel(for row: ApprovalListRow) -> String {
        let typeLabel = row.requestType.displayLabel
        let name = row.requesterProfile?.fullName ?? "未知用户"
        return "\(typeLabel) · \(name)"
    }

    // MARK: - List

    @ViewBuilder
    private var queueList: some View {
        List {
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                NavigationLink(value: row.id) {
                    Group {
                        if let ns = zoomNamespace {
                            queueRow(row)
                                .matchedTransitionSource(id: row.id, in: ns)
                        } else {
                            queueRow(row)
                        }
                    }
                }
                .bsAppearStagger(index: index)
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private func queueRow(_ row: ApprovalListRow) -> some View {
        BsContentCard(padding: .none) {
            VStack(alignment: .leading, spacing: 10) {
                // Header: avatar + name + type + priority + status
                HStack(alignment: .center, spacing: 12) {
                    avatarCircle(row.requesterProfile)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(row.requesterProfile?.fullName ?? "未知用户")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BsColor.ink)

                            typeChip(row.requestType)
                            priorityChip(row.priorityByRequester)
                        }
                        Text(Self.createdAtFormatter.string(from: row.createdAt))
                            .font(.caption2)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    Spacer(minLength: 8)
                    statusChip(row.status)
                }

                // Leave preview line (for .leave queue rows or any row that
                // happens to have a leave join — the `expense`/`generic`
                // queues never do, but the model carries optionals anyway).
                if row.startDate != nil || row.endDate != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(BsColor.inkMuted)
                        Text(leaveSpanText(row))
                            .font(.caption)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }

                if let reason = row.businessReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(2)
                }

                // Action buttons — pending only + kind supports writes.
                // Leave kind surfaces a small hint so the user knows where
                // to go; no buttons there.
                if row.status == .pending {
                    if viewModel.kind.supportsWriteOnIOS {
                        actionRow(for: row)
                    } else {
                        Text("请假审批请在 Web 端完成(涉及请假额度与排班状态同步)")
                            .font(.caption2)
                            .foregroundStyle(BsColor.warning)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Action buttons

    @ViewBuilder
    private func actionRow(for row: ApprovalListRow) -> some View {
        let isBusy = viewModel.busyIds.contains(row.id)
        HStack(spacing: 8) {
            Spacer()

            Button {
                pendingAction = PendingAction(row: row, decision: .approve)
            } label: {
                HStack(spacing: 4) {
                    if isBusy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text("批准").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(BsColor.success)
                .glassEffect(.regular.tint(BsColor.success.opacity(0.28)).interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            Button {
                pendingAction = PendingAction(row: row, decision: .reject)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                    Text("拒绝").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(BsColor.danger)
                .glassEffect(.regular.tint(BsColor.danger.opacity(0.28)).interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func avatarCircle(_ profile: ApprovalActorProfile?) -> some View {
        ZStack {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.15))
                .frame(width: 36, height: 36)
            Text(profile?.initial ?? "?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BsColor.brandAzure)
        }
    }

    @ViewBuilder
    private func typeChip(_ type: ApprovalRequestType) -> some View {
        Text(type.displayLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(BsColor.brandAzure)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular.tint(BsColor.brandAzure.opacity(0.35)), in: Capsule())
    }

    @ViewBuilder
    private func priorityChip(_ priority: RequestPriority) -> some View {
        if priority == .unknown { EmptyView() } else {
            Text(priorityLabel(priority))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(priorityTint(priority))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .glassEffect(.regular.tint(priorityTint(priority).opacity(0.35)), in: Capsule())
        }
    }

    private func priorityLabel(_ p: RequestPriority) -> String {
        switch p {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        case .urgent: return "紧急"
        case .unknown: return ""
        }
    }

    private func priorityTint(_ p: RequestPriority) -> Color {
        switch p {
        case .low:     return BsColor.inkMuted
        case .medium:  return BsColor.brandAzure
        case .high:    return BsColor.warning
        case .urgent:  return BsColor.danger
        case .unknown: return BsColor.inkMuted
        }
    }

    @ViewBuilder
    private func statusChip(_ status: ApprovalStatus) -> some View {
        Text(status.displayLabel)
            .font(.caption2.weight(.medium))
            .foregroundStyle(toneForeground(status.tone))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(toneBackground(status.tone).opacity(1.5)), in: Capsule())
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

    private var emptyDescription: String {
        switch viewModel.kind {
        case .leave:        return "暂无请假审批,待提交的请假申请将显示在此处。"
        case .fieldWork:    return "暂无外勤审批。"
        case .businessTrip: return "暂无出差审批。"
        case .expense:      return "暂无报销/采购审批。"
        case .generic:      return "暂无通用审批。"
        }
    }

    private func leaveSpanText(_ row: ApprovalListRow) -> String {
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

    private static let createdAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
