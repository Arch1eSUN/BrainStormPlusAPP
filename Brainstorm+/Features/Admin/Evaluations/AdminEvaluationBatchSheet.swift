import SwiftUI

// ══════════════════════════════════════════════════════════════════
// AdminEvaluationBatchSheet — 批量 AI 评分入口
//
// POST /api/mobile/admin/evaluations/trigger —— Web 路由内完成
// CRON_SECRET / api_keys 解密 + askAI orchestrator + 入库；
// iOS 只提交 year_month / user_ids / force_regenerate 并等待 triggered 数。
// ══════════════════════════════════════════════════════════════════

public struct AdminEvaluationBatchSheet: View {
    public let month: String
    public let userIds: [UUID]
    public let onTriggered: (Int) -> Void
    /// 由宿主 View 注入：真正调用 /api/mobile/admin/evaluations/trigger
    /// 的方法。失败时在 VM 里写 `errorMessage`，sheet 不自行关闭。
    public let runTrigger: @MainActor ([UUID], Bool) async -> Int?

    @Environment(\.dismiss) private var dismiss
    @State private var forceRegenerate: Bool = false
    @State private var submitting: Bool = false
    @State private var localError: String?
    @State private var successText: String?

    public init(
        month: String,
        userIds: [UUID],
        onTriggered: @escaping (Int) -> Void,
        runTrigger: @escaping @MainActor ([UUID], Bool) async -> Int?
    ) {
        self.month = month
        self.userIds = userIds
        self.onTriggered = onTriggered
        self.runTrigger = runTrigger
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    infoCard
                    optionsCard
                    if let err = localError {
                        errorBanner(err)
                    }
                    if let ok = successText {
                        successBanner(ok)
                    }
                    submitButton
                    Spacer(minLength: 20)
                }
                .padding(16)
            }
            .background(BsColor.pageBackground.ignoresSafeArea())
            .navigationTitle("批量评估")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .disabled(submitting)
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BsColor.brandAzure.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "bolt.horizontal.fill")
                    .font(.title3)
                    .foregroundStyle(BsColor.brandAzure)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 月度批量评估")
                    .font(.headline)
                Text("\(month) · 当前筛选后 \(userIds.count) 位员工")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BsColor.surfacePrimary))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(BsColor.brandAzure)
                Text("执行说明")
                    .font(.subheadline.weight(.semibold))
            }
            Text("单位 = 员工 × 月份。每月每人只保留一条评估。默认仅补跑缺失月份；若选择覆盖，已有评分会被新结果替换。批量任务平均耗时每人约 30s，失败条目不会中断整批。")
                .font(.footnote)
                .foregroundStyle(BsColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BsColor.surfacePrimary))
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $forceRegenerate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("覆盖已有评估")
                        .font(.subheadline.weight(.semibold))
                    Text("打开后即使已有 \(month) 评分也会重跑并替换。")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
            .tint(BsColor.brandAzure)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(BsColor.surfacePrimary))
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BsColor.danger)
            Text(text)
                .font(.footnote)
                .foregroundStyle(BsColor.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BsColor.danger.opacity(0.08)))
    }

    private func successBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(BsColor.success)
            Text(text)
                .font(.footnote)
                .foregroundStyle(BsColor.success)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BsColor.success.opacity(0.08)))
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Text(submitting ? "批量触发中…" : "开始批量评估")
        }
        .buttonStyle(BsPrimaryButtonStyle(size: .large, isLoading: submitting))
        .disabled(userIds.isEmpty || submitting)
    }

    private func submit() async {
        submitting = true
        localError = nil
        successText = nil
        defer { submitting = false }

        if let count = await runTrigger(userIds, forceRegenerate) {
            successText = "已触发 \(count) 个评估"
            onTriggered(count)
            // 给用户 ~0.8s 看到成功态再自动关闭
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } else {
            // VM 会把具体原因写到 errorMessage（外部 banner）；
            // 这里只做保底提示，避免 sheet 看起来毫无反应。
            localError = "批量评估触发失败，请查看顶部错误提示或稍后重试。"
        }
    }
}
