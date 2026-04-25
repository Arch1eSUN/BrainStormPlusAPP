import SwiftUI

/// 1:1 port of Web `ApprovalCommentDialog`
/// (src/app/dashboard/approval/_dialogs/approval-comment-dialog.tsx).
///
/// Rules — enforced BOTH client-side (this sheet) and server-side (the
/// `approvals_apply_action` RPC applies the same guard):
/// - `approve`: comment is optional — empty maps to `nil`
/// - `reject`:  comment is mandatory — empty blocks the confirm button
///
/// The sheet is a dumb input container. Parent is responsible for
/// invoking `applyAction` with the returned comment and closing the
/// sheet on success.
public struct ApprovalCommentSheet: View {
    @Binding public var isPresented: Bool
    public let decision: ApprovalActionDecision
    public let requestLabel: String?
    public let onConfirm: (String?) async -> Bool

    @State private var comment: String = ""
    @State private var isBusy: Bool = false
    @FocusState private var focused: Bool

    public init(
        isPresented: Binding<Bool>,
        decision: ApprovalActionDecision,
        requestLabel: String? = nil,
        onConfirm: @escaping (String?) async -> Bool
    ) {
        self._isPresented = isPresented
        self.decision = decision
        self.requestLabel = requestLabel
        self.onConfirm = onConfirm
    }

    private var trimmed: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isReject: Bool { decision == .reject }

    private var rejectBlocked: Bool { isReject && trimmed.isEmpty }

    private var confirmDisabled: Bool { isBusy || rejectBlocked }

    public var body: some View {
        NavigationStack {
            ZStack {
                BsColor.pageBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                if let label = requestLabel, !label.isEmpty {
                    HStack(spacing: 4) {
                        Text("对象：")
                            .foregroundStyle(BsColor.inkMuted)
                        Text(label)
                            .fontWeight(.medium)
                    }
                    .font(.footnote)
                }

                ZStack(alignment: .topLeading) {
                    if isReject {
                        Rectangle()
                            .fill(BsColor.danger.opacity(0.6))
                            .frame(width: 4)
                            .cornerRadius(2)
                    }
                    TextEditor(text: $comment)
                        .focused($focused)
                        .frame(minHeight: 120, maxHeight: 200)
                        .padding(8)
                        .padding(.leading, isReject ? 4 : 0)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                        .disabled(isBusy)
                        .overlay(alignment: .topLeading) {
                            if comment.isEmpty {
                                Text(placeholder)
                                    .font(.subheadline)
                                    .foregroundStyle(BsColor.inkMuted.opacity(0.7))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 16)
                                    .padding(.leading, isReject ? 4 : 0)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if isReject {
                    Label("拒绝需填写原因（申请人会看到）", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(BsColor.danger)
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button("取消") {
                        if !isBusy {
                            // Haptic removed: 用户反馈辅助按钮过密震动
                            isPresented = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)

                    // Phase 20 集中爆发点 —— sheet 的唯一主 CTA。
                    // BsPrimaryButton 内部已包 Haptic.medium() + 按压反馈。
                    // 注意：rejectBlocked 时 confirmDisabled=true,按钮本身
                    // 被 .disabled 挡掉,原来的 warning haptic 分支已无触达路径,
                    // 所以此处只需处理正常 submit。
                    BsPrimaryButton(size: .regular, isLoading: isBusy) {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isReject ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .font(.system(.subheadline, weight: .semibold))
                            Text("确认")
                        }
                        .foregroundStyle(.white)
                    }
                    .disabled(confirmDisabled)
                    .opacity(confirmDisabled ? 0.55 : 1.0)
                }
                }
            }
            .padding(16)
            .navigationTitle(isReject ? "拒绝审批" : "批准审批")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isBusy)
    }

    private var placeholder: String {
        isReject
            ? "必填：请写明拒绝原因，以便申请人了解"
            : "可选：对批准附加说明（留空也可）"
    }

    private func submit() async {
        guard !confirmDisabled else { return }
        isBusy = true
        defer { isBusy = false }

        // approve: empty → nil; reject: already non-empty via rejectBlocked guard.
        let payload: String? = trimmed.isEmpty ? nil : trimmed
        let ok = await onConfirm(payload)
        if ok {
            Haptic.success()
            isPresented = false
        } else {
            Haptic.error()
        }
        // On failure: keep sheet open. Parent is responsible for surfacing
        // the error banner — matches Web pattern where the dialog stays
        // open when `onConfirm` throws.
    }
}
