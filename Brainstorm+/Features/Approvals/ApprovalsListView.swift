import SwiftUI
import Supabase

/// Sprint 4.1 — "我提交的" list screen (read-only foundation) +
/// Sprint 4.2 — detail push + "申请撤回" self-service.
///
/// 1:1 port of Web `src/app/dashboard/approval/_tabs/my-submissions.tsx`
/// with these intentional deltas:
///   - No tab switcher (Web's page.tsx has 7 tabs for approver queues);
///     this sprint still only surfaces the user-centric "我提交的".
///     4.3 lands the approver queues.
///
/// Navigation entry is via `ActionItemHelper.destination(for: .approval)`
/// which was previously a `ParityBacklogDestination` placeholder. Rows
/// push `ApprovalDetailView` via a value-based NavigationLink.
public struct ApprovalsListView: View {
    @StateObject private var viewModel: MySubmissionsViewModel
    private let client: SupabaseClient

    public init(viewModel: MySubmissionsViewModel, client: SupabaseClient) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.client = client
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.rows.isEmpty {
                ContentUnavailableView(
                    "暂无提交记录",
                    systemImage: "tray",
                    description: Text("你还没有提交过审批申请。")
                )
            } else {
                submissionsList
            }
        }
        .navigationTitle("我提交的")
        .navigationBarTitleDisplayMode(.inline)
        .zyErrorBanner($viewModel.errorMessage)
        .refreshable {
            await viewModel.listMySubmissions()
        }
        .task {
            await viewModel.listMySubmissions()
        }
        .navigationDestination(for: UUID.self) { id in
            ApprovalDetailView(requestId: id, client: client)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var submissionsList: some View {
        List(viewModel.rows) { row in
            NavigationLink(value: row.id) {
                submissionRow(row)
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func submissionRow(_ row: ApprovalMySubmissionRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: type label + status chip + created-at
            HStack(alignment: .center, spacing: 8) {
                Text(row.requestType.displayLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                statusChip(row.status)

                Spacer(minLength: 8)

                Text(Self.createdAtFormatter.string(from: row.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Leave-only preview line (Web my-submissions.tsx:145-151)
            if row.requestType == .leave, let leave = row.leave {
                Text(leavePreviewText(leave))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let reason = row.businessReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }

            if let note = row.reviewerNote, !note.isEmpty {
                // Web: border-l-2 border-gray-200 pl-2 — we mirror with a
                // Rectangle leading bar so the visual semantics carry across.
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                    Text("审批意见：\(note)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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

    // MARK: - Status chip

    @ViewBuilder
    private func statusChip(_ status: ApprovalStatus) -> some View {
        Text(status.displayLabel)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(toneBackground(status.tone))
            )
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

    // MARK: - Leave preview formatter

    private func leavePreviewText(_ leave: ApprovalLeaveDetail) -> String {
        // Matches Web `my-submissions.tsx:146-150` —
        //   `{leave_type} · {start_date} ~ {end_date} · {days} 天`
        // with the leading `{leave_type} · ` segment omitted when leave_type
        // is unknown (Web skips it when falsy; iOS enum always resolves to
        // something — if `unknown`, we also skip rather than show "未知 · …").
        var parts: [String] = []
        if leave.leaveType != .unknown {
            parts.append(leave.leaveType.displayLabel)
        }
        parts.append("\(leave.startDate) ~ \(leave.endDate)")
        parts.append(String(format: "%g 天", leave.days))
        return parts.joined(separator: " · ")
    }

    // MARK: - Date formatter
    //
    // Matches Web `formatDate` (my-submissions.tsx:32-37): "YYYY-MM-DD HH:mm".
    // Kept private-static so we don't reallocate per row render.

    private static let createdAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

#Preview {
    NavigationStack {
        ApprovalsListView(
            viewModel: MySubmissionsViewModel(client: supabase),
            client: supabase
        )
    }
}
