import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.2 — Approval detail screen.
//
// 1:1 port of Web `ApprovalDetailDialog`
// (`src/app/dashboard/approval/_dialogs/approval-detail-dialog.tsx`).
// Section order, labels, and gating all mirror Web. Divergences:
//   - iOS ships as a pushed NavigationStack screen, not a centered
//     modal dialog — navigation parity with other list → detail flows
//     in the app (tasks, projects, knowledge).
//   - `isSelf` badge is dropped: every row reachable from "我提交的"
//     is already self-served. 4.3 will revisit when we land the
//     approver queues.
//   - AI assist audit list is omitted for 4.2 (Web shows a collapsed
//     list of the last 5 — not user-facing value). Carry-forward.
//   - Revoke flow renders as a sheet instead of a centered dialog;
//     still calls the same SECURITY DEFINER RPC.
// ══════════════════════════════════════════════════════════════════

public struct ApprovalDetailView: View {
    @StateObject private var viewModel: ApprovalDetailViewModel
    @State private var showRevokeSheet = false

    public init(requestId: UUID, client: SupabaseClient) {
        _viewModel = StateObject(
            wrappedValue: ApprovalDetailViewModel(requestId: requestId, client: client)
        )
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.request == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let request = viewModel.request {
                detailScroll(request)
            } else if let message = viewModel.errorMessage {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            } else {
                ContentUnavailableView(
                    "审批请求不存在",
                    systemImage: "tray"
                )
            }
        }
        .navigationTitle("审批详情")
        .navigationBarTitleDisplayMode(.inline)
        .zyErrorBanner($viewModel.errorMessage)
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showRevokeSheet) {
            revokeSheet
        }
    }

    // MARK: - Detail body

    @ViewBuilder
    private func detailScroll(_ request: ApprovalRequestDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard(request)

                if let reason = request.businessReason, !reason.isEmpty {
                    Section(title: "申请事由", systemImage: "bubble.left.and.text.bubble.right") {
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                typedDetailSection(viewModel.typedDetail)

                if !request.attachments.isEmpty {
                    Section(title: "附件", systemImage: "paperclip") {
                        attachmentsList(request.attachments)
                    }
                }

                if let summary = request.aiSummary, !summary.isEmpty {
                    Section(title: "AI 摘要", systemImage: "sparkles") {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let note = request.reviewerNote, !note.isEmpty {
                    Section(title: "审批意见", systemImage: "checkmark.seal") {
                        reviewerNoteBlock(note: note, at: request.reviewedAt)
                    }
                }

                if !viewModel.actions.isEmpty {
                    Section(title: "审批记录", systemImage: "clock.badge.checkmark") {
                        auditTrail(viewModel.actions)
                    }
                }

                if viewModel.canRevokeCompTime {
                    revokeAffordance
                }
            }
            .padding(16)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerCard(_ request: ApprovalRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                avatarCircle(request.requesterProfile)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(request.requesterProfile?.fullName ?? "未知用户")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        typeChip(request.requestType)

                        statusChip(request.status)
                    }
                    Text(submittedAtText(request))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func avatarCircle(_ profile: ApprovalActorProfile?) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 44, height: 44)
            Text(profile?.initial ?? "?")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
        }
    }

    @ViewBuilder
    private func typeChip(_ type: ApprovalRequestType) -> some View {
        Text(type.displayLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.blue.opacity(0.15))
            )
            .foregroundStyle(Color.blue)
    }

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

    private func submittedAtText(_ request: ApprovalRequestDetail) -> String {
        let ts = request.requestedAt ?? request.createdAt
        var pieces = ["提交时间：\(Self.dtFormatter.string(from: ts))"]
        if let dep = request.requesterProfile?.department, !dep.isEmpty {
            pieces.append(dep)
        }
        return pieces.joined(separator: " · ")
    }

    // MARK: - Typed detail dispatcher

    @ViewBuilder
    private func typedDetailSection(_ typed: ApprovalTypedDetail) -> some View {
        switch typed {
        case .leave(let leave):
            Section(title: "请假信息", systemImage: "calendar") {
                KeyValue(label: "请假类型", value: leave.leaveType.displayLabel)
                KeyValue(label: "开始日期", value: leave.startDate)
                KeyValue(label: "结束日期", value: leave.endDate)
                KeyValue(label: "天数", value: String(format: "%g 天", leave.days))
                if let hours = leave.hours {
                    KeyValue(label: "小时数", value: String(format: "%g 小时", hours))
                }
                if let reason = leave.reason, !reason.isEmpty {
                    KeyValue(label: "原因", value: reason)
                }
                if leave.medicalCertRequired == true {
                    KeyValue(
                        label: "医疗证明",
                        value: (leave.medicalCertUploaded ?? false) ? "已上传" : "未上传"
                    )
                }
            }

        case .reimbursement(let r):
            Section(title: "报销信息", systemImage: "creditcard") {
                if let v = r.itemDescription { KeyValue(label: "报销项目", value: v) }
                if let v = r.category { KeyValue(label: "类别", value: v) }
                if let v = r.purchaseDate { KeyValue(label: "消费日期", value: v) }
                KeyValue(label: "金额", value: formatCents(r.amount, currency: r.currency))
                if let v = r.merchant { KeyValue(label: "商户", value: v) }
                if let v = r.paymentMethod { KeyValue(label: "支付方式", value: v) }
                if let v = r.purpose { KeyValue(label: "用途", value: v) }
                if !r.receiptUrls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("票据")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(r.receiptUrls.enumerated()), id: \.offset) { idx, receipt in
                            receiptLink(idx: idx, receipt: receipt)
                        }
                    }
                    .padding(.top, 6)
                }
            }

        case .procurement(let p):
            Section(title: "采购信息", systemImage: "cart") {
                if let v = p.procurementType { KeyValue(label: "采购类型", value: v) }
                if let v = p.itemDescription { KeyValue(label: "物品描述", value: v) }
                if let v = p.vendor { KeyValue(label: "供应商", value: v) }
                if let q = p.quantity { KeyValue(label: "数量", value: "\(q)") }
                KeyValue(label: "单价", value: formatCents(p.unitPrice, currency: p.currency))
                KeyValue(label: "总价", value: formatCents(p.totalPrice, currency: p.currency))
                if let v = p.userOrDepartment { KeyValue(label: "使用方", value: v) }
                if let v = p.purpose { KeyValue(label: "用途", value: v) }
                if let v = p.alternativesConsidered { KeyValue(label: "备选方案", value: v) }
                if let v = p.justification { KeyValue(label: "理由", value: v) }
                if let b = p.budgetAvailable {
                    KeyValue(label: "预算是否充足", value: b ? "是" : "否")
                }
                if let v = p.expectedPurchaseDate { KeyValue(label: "预计采购日期", value: v) }
            }

        case .fieldWork(let f):
            Section(title: "外勤信息", systemImage: "mappin.and.ellipse") {
                if let v = f.targetDate { KeyValue(label: "日期", value: v) }
                if let v = f.location { KeyValue(label: "地点", value: v) }
                if let v = f.reason { KeyValue(label: "事由", value: v) }
                if let v = f.expectedReturn { KeyValue(label: "预计返程", value: v) }
            }

        case .businessTrip(let t):
            Section(title: "出差信息", systemImage: "airplane") {
                if let v = t.destination { KeyValue(label: "目的地", value: v) }
                if let v = t.startDate { KeyValue(label: "开始日期", value: v) }
                if let v = t.endDate { KeyValue(label: "结束日期", value: v) }
                if let v = t.purpose { KeyValue(label: "事由", value: v) }
                if let v = t.transportation { KeyValue(label: "交通方式", value: v) }
                if let cost = t.estimatedCost {
                    KeyValue(label: "预计费用", value: String(format: "¥%.2f", cost))
                }
                if let v = t.cancellationReason { KeyValue(label: "取消原因", value: v) }
            }

        case .report(let r):
            Section(
                title: r.bodyWeekStart != nil ? "周报内容" : "日报内容",
                systemImage: "doc.text"
            ) {
                reportFields(r)
            }

        case .revokeCompTime(let rct):
            Section(title: "撤回调休", systemImage: "arrow.uturn.backward") {
                if let v = rct.reason, !v.isEmpty {
                    KeyValue(label: "撤回事由", value: v)
                }
                if let s = rct.originalStartDate, let e = rct.originalEndDate {
                    let window = s == e ? s : "\(s) → \(e)"
                    KeyValue(label: "原调休区间", value: window)
                }
                KeyValue(
                    label: "原申请 ID",
                    value: String(rct.originalApprovalId.uuidString.prefix(8)) + "…"
                )
            }

        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func reportFields(_ r: ApprovalReportDetail) -> some View {
        let isWeekly = r.bodyWeekStart != nil || r.accomplishments != nil
        if isWeekly {
            if let s = r.bodyWeekStart ?? r.weekStart {
                KeyValue(label: "周期", value: "\(s) ~ \(r.bodyWeekEnd ?? "—")")
            }
            if let v = r.accomplishments, !v.isEmpty { KeyValue(label: "工作成果", value: v) }
            if let v = r.plans, !v.isEmpty { KeyValue(label: "下周计划", value: v) }
            if let v = r.blockers, !v.isEmpty { KeyValue(label: "阻碍 / 挑战", value: v) }
            if let v = r.summary, !v.isEmpty { KeyValue(label: "总结", value: v) }
        } else {
            if let v = r.reportDate ?? r.bodyDate { KeyValue(label: "日期", value: v) }
            if let v = r.mood, !v.isEmpty { KeyValue(label: "心情", value: v) }
            if let v = r.progress, !v.isEmpty { KeyValue(label: "进度", value: v) }
            if let v = r.blockers, !v.isEmpty { KeyValue(label: "阻碍", value: v) }
            if let v = r.content, !v.isEmpty { KeyValue(label: "内容", value: v) }
        }
    }

    // MARK: - Attachments

    @ViewBuilder
    private func attachmentsList(_ items: [ApprovalAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = item.url, let parsed = URL(string: url) {
                        Link(item.displayName, destination: parsed)
                            .font(.subheadline)
                            .foregroundStyle(Color.blue)
                    } else {
                        Text(item.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func receiptLink(idx: Int, receipt: ApprovalReceiptLink) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(Color.blue.opacity(0.8))
            if let url = URL(string: receipt.url) {
                Link("票据 \(idx + 1)", destination: url)
                    .font(.caption)
                    .foregroundStyle(Color.blue)
            } else {
                Text("票据 \(idx + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Reviewer note

    @ViewBuilder
    private func reviewerNoteBlock(note: String, at reviewedAt: Date?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let at = reviewedAt {
                    Text("于 \(Self.dtFormatter.string(from: at)) 审批")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Audit trail

    @ViewBuilder
    private func auditTrail(_ actions: [ApprovalAuditLogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(actions) { entry in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Text(entry.actor?.initial ?? "?")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(entry.actor?.fullName ?? "未知用户")
                                .font(.subheadline.weight(.semibold))
                            actionTypeChip(entry.actionType)
                            Text(Self.dtFormatter.string(from: entry.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let comment = entry.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func actionTypeChip(_ type: ApprovalActionType) -> some View {
        Text(type.displayLabel)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(toneBackground(type.tone))
            )
            .foregroundStyle(toneForeground(type.tone))
    }

    // MARK: - Revoke affordance + sheet

    @ViewBuilder
    private var revokeAffordance: some View {
        Button {
            showRevokeSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                Text("申请撤回")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.15))
            )
            .foregroundStyle(Color.orange)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var revokeSheet: some View {
        RevokeCompTimeSheet(
            window: viewModel.compTimeWindow,
            originalApprovalId: viewModel.request?.id,
            isSubmitting: viewModel.isSubmittingRevoke,
            onSubmit: { reason in
                Task {
                    let ok = await viewModel.submitRevokeCompTime(reason: reason)
                    if ok { showRevokeSheet = false }
                }
            },
            onCancel: {
                showRevokeSheet = false
            }
        )
    }

    // MARK: - Tone mapping

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

    // MARK: - Helpers

    private func formatCents(_ amount: Int?, currency: String?) -> String {
        guard let amount = amount else { return "—" }
        let yuan = Double(amount) / 100.0
        let symbol: String
        if let c = currency, !c.isEmpty {
            symbol = c == "CNY" ? "¥" : "\(c) "
        } else {
            symbol = "¥"
        }
        return String(format: "\(symbol)%.2f", yuan)
    }

    private static let dtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

// ─── Section wrapper (local, kept off-model-layer) ───────────────

private struct Section<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// ─── Key-value row (local) ───────────────────────────────────────

private struct KeyValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

// ─── Revoke comp-time sheet ──────────────────────────────────────

private struct RevokeCompTimeSheet: View {
    let window: (start: String, end: String)?
    let originalApprovalId: UUID?
    let isSubmitting: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var reason: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    VStack(alignment: .leading, spacing: 6) {
                        Text("撤回事由")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $reason)
                            .focused($focused)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }

                    Text("撤回申请经审批通过后，调休额度将返还，且对应日期的工作状态会重新派生。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .navigationTitle("申请撤回调休")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSubmit(reason)
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("提交")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSubmitting || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                Text("原调休区间")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            if let w = window {
                let windowText = w.start == w.end ? w.start : "\(w.start) → \(w.end)"
                Text(windowText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let id = originalApprovalId {
                Text("原申请 ID: \(String(id.uuidString.prefix(8)))…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.yellow.opacity(0.08))
        )
    }
}

#Preview {
    NavigationStack {
        ApprovalDetailView(
            requestId: UUID(),
            client: supabase
        )
    }
}
