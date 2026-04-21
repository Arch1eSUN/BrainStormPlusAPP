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

    public init(kind: ApprovalQueueKind, client: SupabaseClient) {
        _viewModel = StateObject(wrappedValue: ApprovalQueueViewModel(kind: kind, client: client))
        self.client = client
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
    }

    // MARK: - List

    @ViewBuilder
    private var queueList: some View {
        List(viewModel.rows) { row in
            NavigationLink(value: row.id) {
                queueRow(row)
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func queueRow(_ row: ApprovalListRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: avatar + name + type + priority + status
            HStack(alignment: .center, spacing: 12) {
                avatarCircle(row.requesterProfile)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.requesterProfile?.fullName ?? "未知用户")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        typeChip(row.requestType)
                        priorityChip(row.priorityByRequester)
                    }
                    Text(Self.createdAtFormatter.string(from: row.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    Text(leaveSpanText(row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let reason = row.businessReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(Color.orange)
                        .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Action buttons

    @ViewBuilder
    private func actionRow(for row: ApprovalListRow) -> some View {
        let isBusy = viewModel.busyIds.contains(row.id)
        HStack(spacing: 8) {
            Spacer()

            Button {
                Task { await viewModel.applyAction(to: row.id, decision: .approve, comment: nil) }
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
                .background(Capsule().fill(Color.green))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            Button {
                Task { await viewModel.applyAction(to: row.id, decision: .reject, comment: nil) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                    Text("拒绝").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .strokeBorder(Color.red.opacity(0.5), lineWidth: 1)
                        .background(Capsule().fill(Color.red.opacity(0.08)))
                )
                .foregroundStyle(Color.red)
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
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 36, height: 36)
            Text(profile?.initial ?? "?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private func typeChip(_ type: ApprovalRequestType) -> some View {
        Text(type.displayLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.blue.opacity(0.15)))
            .foregroundStyle(Color.blue)
    }

    @ViewBuilder
    private func priorityChip(_ priority: RequestPriority) -> some View {
        if priority == .unknown { EmptyView() } else {
            Text(priorityLabel(priority))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(priorityTint(priority).opacity(0.15)))
                .foregroundStyle(priorityTint(priority))
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
        case .low:     return .gray
        case .medium:  return .blue
        case .high:    return .orange
        case .urgent:  return .red
        case .unknown: return .gray
        }
    }

    @ViewBuilder
    private func statusChip(_ status: ApprovalStatus) -> some View {
        Text(status.displayLabel)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(toneBackground(status.tone)))
            .foregroundStyle(toneForeground(status.tone))
    }

    private func toneBackground(_ tone: ApprovalStatus.Tone) -> Color {
        switch tone {
        case .warning: return Color.orange.opacity(0.15)
        case .success: return Color.green.opacity(0.15)
        case .danger:  return Color.red.opacity(0.15)
        case .info:    return Color.blue.opacity(0.15)
        case .neutral: return Color.gray.opacity(0.18)
        }
    }

    private func toneForeground(_ tone: ApprovalStatus.Tone) -> Color {
        switch tone {
        case .warning: return Color.orange
        case .success: return Color.green
        case .danger:  return Color.red
        case .info:    return Color.blue
        case .neutral: return Color.secondary
        }
    }

    private var emptyDescription: String {
        switch viewModel.kind {
        case .leave:        return "暂无请假审批,待提交的请假申请将显示在此处。"
        case .fieldWork:    return "暂无外勤审批。"
        case .businessTrip: return "暂无出差审批。"
        case .expense:      return "暂无报销/采购审批。"
        case .report:       return "暂无日报/周报审批。"
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
