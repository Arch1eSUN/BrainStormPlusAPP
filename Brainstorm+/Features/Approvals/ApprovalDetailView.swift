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
//   - AI assist audit list is omitted for 4.2 (Web shows a collapsed
//     list of the last 5 — not user-facing value). Carry-forward.
//   - Revoke flow renders as a sheet instead of a centered dialog;
//     still calls the same SECURITY DEFINER RPC.
//
// Batch C.1 additions:
//   - `isSelf` "本人提交" pill (Web parity: approval-detail-dialog.tsx:228).
//   - Bottom action bar with approve/reject for pending rows when
//     the viewer holds the matching capability. Routes through the
//     existing `ApprovalCommentSheet` so comment rules (reject
//     requires comment; approve optional) are enforced uniformly.
// ══════════════════════════════════════════════════════════════════

public struct ApprovalDetailView: View {
    @Environment(SessionManager.self) private var sessionManager
    @StateObject private var viewModel: ApprovalDetailViewModel
    @State private var showRevokeSheet = false
    @State private var pendingDecision: ApprovalActionDecision?

    public init(requestId: UUID, client: SupabaseClient) {
        _viewModel = StateObject(
            wrappedValue: ApprovalDetailViewModel(requestId: requestId, client: client)
        )
    }

    private var effectiveCapabilities: [Capability] {
        RBACManager.shared.getEffectiveCapabilities(for: sessionManager.currentProfile)
    }

    private var canShowActionBar: Bool {
        viewModel.canApproveThisRequest(capabilities: effectiveCapabilities)
            // Leave kind routes through the Next.js hook layer on Web
            // for comp_time quota / DWS side-effects. Keep the same
            // "Web-only" gate as the queue list (parity with
            // `ApprovalQueueKind.supportsWriteOnIOS`).
            && viewModel.request?.requestType != .leave
    }

    public var body: some View {
        ZStack {
            // Ambient 弥散底层 —— Azure + Mint blobs 漂在暖米纸底上，
            // 卡片玻璃透出一点氛围光。Fusion 词汇统一。
            BsColor.pageBackground.ignoresSafeArea()

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
        }
        .navigationTitle("审批详情")
        .navigationBarTitleDisplayMode(.inline)
        // 长按整页 → 复制编号（对齐 Fusion 交互词汇）
        .bsContextMenu([
            BsContextMenuItem(
                label: "复制编号",
                systemImage: "doc.on.doc"
            ) {
                if let id = viewModel.request?.id {
                    UIPasteboard.general.string = id.uuidString
                    Haptic.light()
                }
            }
        ])
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
        .sheet(item: $pendingDecision) { decision in
            ApprovalCommentSheet(
                isPresented: Binding(
                    get: { pendingDecision != nil },
                    set: { if !$0 { pendingDecision = nil } }
                ),
                decision: decision,
                requestLabel: actionSheetLabel
            ) { comment in
                await viewModel.applyAction(decision: decision, comment: comment)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if canShowActionBar {
                actionBar
            }
        }
    }

    private var actionSheetLabel: String? {
        guard let req = viewModel.request else { return nil }
        let typeLabel = req.requestType.displayLabel
        let name = req.requesterProfile?.fullName ?? "未知用户"
        return "\(typeLabel) · \(name)"
    }

    @ViewBuilder
    private var actionBar: some View {
        let busy = viewModel.isApplyingAction
        HStack(spacing: 12) {
            // 拒绝 —— glass-tinted danger capsule + warning haptic
            Button(role: .destructive) {
                Haptic.warning()
                pendingDecision = .reject
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                    Text("拒绝").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .glassEffect(
                    .regular.tint(BsColor.danger.opacity(0.28)).interactive(),
                    in: Capsule()
                )
                .foregroundStyle(BsColor.danger)
            }
            .buttonStyle(.plain)
            .disabled(busy)

            // 批准 —— glass-tinted success capsule + success haptic
            Button {
                Haptic.success()
                pendingDecision = .approve
            } label: {
                HStack(spacing: 6) {
                    if busy {
                        ProgressView().controlSize(.small).tint(BsColor.success)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text("批准").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .glassEffect(
                    .regular.tint(BsColor.success.opacity(0.28)).interactive(),
                    in: Capsule()
                )
                .foregroundStyle(BsColor.success)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Detail body

    @ViewBuilder
    private func detailScroll(_ request: ApprovalRequestDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 入场 stagger —— 每张卡延迟 50ms 按序浮入
                headerCard(request)
                    .bsAppearStagger(index: 0)

                if let reason = request.businessReason, !reason.isEmpty {
                    Section(title: "申请事由", systemImage: "bubble.left.and.text.bubble.right") {
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(BsColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .bsAppearStagger(index: 1)
                }

                typedDetailSection(viewModel.typedDetail)
                    .bsAppearStagger(index: 2)

                if !request.attachments.isEmpty {
                    Section(title: "附件", systemImage: "paperclip") {
                        attachmentsList(request.attachments)
                    }
                    .bsAppearStagger(index: 3)
                }

                if let summary = request.aiSummary, !summary.isEmpty {
                    Section(title: "AI 摘要", systemImage: "sparkles") {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(BsColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .bsAppearStagger(index: 4)
                }

                if let note = request.reviewerNote, !note.isEmpty {
                    Section(title: "审批意见", systemImage: "checkmark.seal") {
                        reviewerNoteBlock(note: note, at: request.reviewedAt)
                    }
                    .bsAppearStagger(index: 5)
                }

                if !viewModel.actions.isEmpty {
                    Section(title: "审批记录", systemImage: "clock.badge.checkmark") {
                        auditTrail(viewModel.actions)
                    }
                    .bsAppearStagger(index: 6)
                }

                if viewModel.canRevokeCompTime {
                    revokeAffordance
                        .bsAppearStagger(index: 7)
                }
            }
            .padding(16)
        }
        // Ambient bg 直接透到 scroll 下层
        .scrollContentBackground(.hidden)
    }

    // MARK: - Header

    @ViewBuilder
    private func headerCard(_ request: ApprovalRequestDetail) -> some View {
        BsContentCard(padding: .none) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    avatarCircle(request.requesterProfile)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(request.requesterProfile?.fullName ?? "未知用户")
                                .font(.headline)
                                .foregroundStyle(BsColor.ink)

                            typeChip(request.requestType)

                            statusChip(request.status)

                            if viewModel.isSelf {
                                selfPill
                            }
                        }
                        Text(submittedAtText(request))
                            .font(.caption2)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func avatarCircle(_ profile: ApprovalActorProfile?) -> some View {
        ZStack {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.15))
                .frame(width: 44, height: 44)
            Text(profile?.initial ?? "?")
                .font(.headline)
                .foregroundStyle(BsColor.brandAzure)
        }
        .accessibilityLabel(profile?.fullName ?? "用户")
    }

    @ViewBuilder
    private func typeChip(_ type: ApprovalRequestType) -> some View {
        Text(type.displayLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassEffect(
                .regular.tint(BsColor.brandAzure.opacity(0.25)),
                in: Capsule()
            )
            .foregroundStyle(BsColor.brandAzure)
    }

    @ViewBuilder
    private func statusChip(_ status: ApprovalStatus) -> some View {
        Text(status.displayLabel)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(
                .regular.tint(toneForeground(status.tone).opacity(0.25)),
                in: Capsule()
            )
            .foregroundStyle(toneForeground(status.tone))
    }

    /// Emerald "我提交的" pill shown in the header when viewer == requester.
    /// Mirrors Web `approval-detail-dialog.tsx:228-233` (emerald chip with
    /// user icon). Rendered only after `load()` resolves `viewerUserId`
    /// and the VM's `isSelf` derived property flips to true.
    @ViewBuilder
    private var selfPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.fill")
                .font(.caption2)
            Text("我提交的")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .glassEffect(
            .regular.tint(BsColor.success.opacity(0.25)),
            in: Capsule()
        )
        .foregroundStyle(BsColor.success)
        .accessibilityLabel("我提交的审批")
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
                            .foregroundStyle(BsColor.inkMuted)
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
                        .foregroundStyle(BsColor.inkMuted)
                    if let url = item.url, let parsed = URL(string: url) {
                        Link(item.displayName, destination: parsed)
                            .font(.subheadline)
                            .foregroundStyle(BsColor.brandAzure)
                    } else {
                        Text(item.displayName)
                            .font(.subheadline)
                            .foregroundStyle(BsColor.inkMuted)
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
                .foregroundStyle(BsColor.brandAzure.opacity(0.8))
            if let url = URL(string: receipt.url) {
                Link("票据 \(idx + 1)", destination: url)
                    .font(.caption)
                    .foregroundStyle(BsColor.brandAzure)
            } else {
                Text("票据 \(idx + 1)")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
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
                    .foregroundStyle(BsColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let at = reviewedAt {
                    Text("于 \(Self.dtFormatter.string(from: at)) 审批")
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkMuted)
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
                            .fill(BsColor.brandAzure.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Text(entry.actor?.initial ?? "?")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BsColor.brandAzure)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(entry.actor?.fullName ?? "未知用户")
                                .font(.subheadline.weight(.semibold))
                            actionTypeChip(entry.actionType)
                            Text(Self.dtFormatter.string(from: entry.createdAt))
                                .font(.caption2)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                        if let comment = entry.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.caption)
                                .foregroundStyle(BsColor.inkMuted)
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
            .glassEffect(
                .regular.tint(toneForeground(type.tone).opacity(0.25)),
                in: Capsule()
            )
            .foregroundStyle(toneForeground(type.tone))
    }

    // MARK: - Revoke affordance + sheet

    @ViewBuilder
    private var revokeAffordance: some View {
        Button {
            Haptic.rigid()
            showRevokeSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                Text("申请撤回")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glassEffect(
                .regular.tint(BsColor.warning.opacity(0.28)).interactive(),
                in: Capsule()
            )
            .foregroundStyle(BsColor.warning)
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
        BsContentCard(padding: .none) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BsColor.inkMuted)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BsColor.inkMuted)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                }
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                .foregroundStyle(BsColor.inkMuted)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(BsColor.ink)
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
                            .foregroundStyle(BsColor.inkMuted)
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
                        .foregroundStyle(BsColor.inkMuted)
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
                        Haptic.medium()
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
                    .foregroundStyle(BsColor.warning)
                Text("原调休区间")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BsColor.ink)
            }
            if let w = window {
                let windowText = w.start == w.end ? w.start : "\(w.start) → \(w.end)"
                Text(windowText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BsColor.ink)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(BsColor.inkMuted)
            }
            if let id = originalApprovalId {
                Text("原申请 ID: \(String(id.uuidString.prefix(8)))…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(BsColor.inkMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(BsColor.warning.opacity(0.15)),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
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
    .environment(SessionManager())
}
