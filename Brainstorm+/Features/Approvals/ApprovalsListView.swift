import SwiftUI
import UIKit
import Supabase

/// Sprint 4.1 — "我提交的" list screen (read-only foundation) +
/// Sprint 4.2 — detail push + "申请撤回" self-service +
/// Sprint 4.3 — embedded as the `mine` tab body inside
/// `ApprovalCenterView` +
/// Design-system adoption — iOS 26 native list idioms
/// (swipeActions / contextMenu / design tokens / haptics).
///
/// 1:1 port of Web `src/app/dashboard/approval/_tabs/my-submissions.tsx`
/// with these intentional deltas:
///   - No tab switcher lives in *this* file; the 7-tab shell is
///     `ApprovalCenterView` (4.3). This view is a content body
///     that assumes it's embedded inside an outer NavigationStack
///     which also owns the `.navigationDestination(for: UUID.self)`
///     registration. We do not declare the destination here to
///     avoid a duplicate-registration SwiftUI runtime warning;
///     the outer center view handles UUID deep links for both
///     `mine` and the 6 approver queues uniformly.
///   - Navigation title/chrome is set by the center view, not this
///     body — the title there is "审批中心" with the pill bar
///     identifying the current tab.
///   - `MySubmissionsViewModel` does not (yet) expose a withdraw
///     action, so the swipeActions/contextMenu "撤回" item is
///     intentionally *not* rendered here. Withdraw still lives in
///     the detail screen (`ApprovalDetailView`) which owns the
///     mutating VM. When `MySubmissionsViewModel.withdrawSubmission`
///     lands, revive the commented hook in `rowContextMenu`.
public struct ApprovalsListView: View {
    @StateObject private var viewModel: MySubmissionsViewModel
    private let client: SupabaseClient
    /// Phase 24 — zoom transition source namespace. Owned by the
    /// enclosing `ApprovalCenterView` so the row and the detail view
    /// (whose `.navigationDestination` registration lives upstream)
    /// share the same identity scope. Optional so previews / ad-hoc
    /// embeddings without a namespace still compile.
    private let zoomNamespace: Namespace.ID?

    public init(
        viewModel: MySubmissionsViewModel,
        client: SupabaseClient,
        zoomNamespace: Namespace.ID? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.client = client
        self.zoomNamespace = zoomNamespace
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.rows.isEmpty {
                // Bug-fix(审批中心视图奇怪): 同 ApprovalQueueView，empty 撑满避免
                // pillBar 被居中推位。
                BsEmptyState(
                    title: "暂无提交记录",
                    systemImage: "tray",
                    description: "你还没有提交过审批申请。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                submissionsList
            }
        }
        // Nav title + UUID deep-link destination are owned by the outer
        // `ApprovalCenterView` (4.3). This body just handles content +
        // pull-to-refresh.
        .zyErrorBanner($viewModel.errorMessage)
        .refreshable {
            await viewModel.listMySubmissions()
        }
        .task {
            await viewModel.listMySubmissions()
        }
    }

    // MARK: - List

    @ViewBuilder
    private var submissionsList: some View {
        List {
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
            NavigationLink(value: row.id) {
                Group {
                    if let ns = zoomNamespace {
                        submissionRow(row)
                            .matchedTransitionSource(id: row.id, in: ns)
                    } else {
                        submissionRow(row)
                    }
                }
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
            // Light haptic on tap so the push into detail has the same
            // feel as Dashboard cards (DashboardRoleSections.swift:217).
            .simultaneousGesture(
                TapGesture().onEnded { Haptic.light() }
            )
            // iOS 26 native swipe — destructive withdraw is the Web parity
            // action here, but MySubmissionsViewModel doesn't own it yet
            // (withdraw lives in ApprovalDetailViewModel). Leaving the
            // trailing edge empty rather than inventing a VM method.
            // When the VM gains `withdrawSubmission(rowId:)`, uncomment:
            //
            // .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            //     if row.status == .pending {
            //         Button(role: .destructive) {
            //             Haptic.rigid()
            //             Task { await viewModel.withdrawSubmission(rowId: row.id) }
            //         } label: {
            //             Label("撤回", systemImage: "arrow.uturn.backward")
            //         }
            //     }
            // }
            .contextMenu { rowContextMenu(row) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func rowContextMenu(_ row: ApprovalMySubmissionRow) -> some View {
        // 查看详情 — always available. Tapping the row already pushes
        // the detail; this entry is the explicit long-press affordance
        // that matches iOS 26 Mail / Messages convention.
        NavigationLink(value: row.id) {
            Label("查看详情", systemImage: "arrow.up.forward.square")
        }

        // 复制编号 — copies the request UUID to UIPasteboard so users
        // can paste it into a support ticket / chat. We copy the raw
        // UUID string (no prefix) to match what the Web admin surface
        // displays in `id` columns.
        Button {
            UIPasteboard.general.string = row.id.uuidString
            Haptic.light()
        } label: {
            Label("复制编号", systemImage: "doc.on.doc")
        }

        // 撤回 — intentionally omitted: MySubmissionsViewModel does
        // not own a withdraw mutation. Withdraw stays on
        // ApprovalDetailView where the VM does own it. See file
        // header for re-enablement note.
    }

    @ViewBuilder
    private func submissionRow(_ row: ApprovalMySubmissionRow) -> some View {
        BsContentCard(padding: .none) {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                // Header: type label + status chip + created-at
                HStack(alignment: .center, spacing: BsSpacing.sm) {
                    Text(row.requestType.displayLabel)
                        .font(BsTypography.cardSubtitle)
                        .foregroundStyle(BsColor.ink)

                    statusChip(row.status)

                    Spacer(minLength: BsSpacing.sm)

                    Text(Self.createdAtFormatter.string(from: row.createdAt))
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkFaint)
                }

                // Leave-only preview line (Web my-submissions.tsx:145-151)
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
                    // Web: border-l-2 border-gray-200 pl-2 — mirror with a
                    // Rectangle leading bar so the visual semantics carry
                    // across.
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

    // MARK: - Status chip

    @ViewBuilder
    private func statusChip(_ status: ApprovalStatus) -> some View {
        Text(status.displayLabel)
            .font(BsTypography.captionSmall)
            .foregroundStyle(toneForeground(status.tone))
            .padding(.horizontal, BsSpacing.sm)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(toneBackground(status.tone).opacity(1.5)), in: Capsule())
    }

    private func toneBackground(_ tone: ApprovalStatus.Tone) -> Color {
        switch tone {
        case .warning: return BsColor.warning.opacity(0.15)
        case .success: return BsColor.success.opacity(0.15)
        case .danger:  return BsColor.danger.opacity(0.15)
        case .info:    return BsColor.brandAzure.opacity(0.15)
        case .neutral: return BsColor.inkMuted.opacity(0.15)
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
    // Preview shell: mirrors what ApprovalCenterView provides at
    // runtime — an outer NavigationStack + the UUID destination
    // registration — so row taps resolve during preview.
    NavigationStack {
        ApprovalsListView(
            viewModel: MySubmissionsViewModel(client: supabase),
            client: supabase
        )
        .navigationTitle("我提交的")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { id in
            ApprovalDetailView(requestId: id, client: supabase)
        }
    }
}
