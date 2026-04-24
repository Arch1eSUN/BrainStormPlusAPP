import SwiftUI
import Charts

// ══════════════════════════════════════════════════
// AIAnalysisView — 1:1 port of
// BrainStorm+-Web/src/app/dashboard/ai-analysis/page.tsx
// Streams `/api/ai/analyze` SSE, renders the same intel-card layout.
// All strings 简体中文.
// ══════════════════════════════════════════════════

public struct AIAnalysisView: View {
    @StateObject private var viewModel: AIAnalysisViewModel
    @Environment(SessionManager.self) private var sessionManager

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    @MainActor
    public init(isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: AIAnalysisViewModel())
        self.isEmbedded = isEmbedded
    }

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        Group {
            if hasAccess {
                main
            } else {
                ContentUnavailableView(
                    "无权访问",
                    systemImage: "lock",
                    description: Text("需要「ai_media_analysis」能力才能使用媒体智能分析。请联系管理员分配。")
                )
            }
        }
        .navigationTitle("媒体智能分析")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if hasAccess && viewModel.provider == nil {
                await viewModel.loadProvider()
            }
        }
        .zyErrorBanner($viewModel.errorMessage)
    }

    private var hasAccess: Bool {
        let caps = RBACManager.shared.getEffectiveCapabilities(for: sessionManager.currentProfile)
        return caps.contains(.ai_media_analysis) || caps.contains(.media_ops)
    }

    private var main: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                if let msg = viewModel.providerLoadError, viewModel.provider == nil, isIdleLike {
                    providerWarning(msg)
                }

                if isIdleLike {
                    inputForm
                } else {
                    progressSection
                    scrapedDataSection
                    reportSection
                    actionBar
                }

                if case .idle = viewModel.pageState, viewModel.providerLoadError == nil {
                    emptyHint
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
    }

    private var isIdleLike: Bool {
        switch viewModel.pageState {
        case .idle, .error: return true
        case .streaming, .done: return false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BsColor.brandAzure, BsColor.brandMint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("媒体智能分析")
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(BsColor.ink)
                HStack(spacing: 6) {
                    Text("社交媒体内容智能分析 ·")
                        .font(.footnote)
                        .foregroundStyle(BsColor.inkMuted)
                    if let p = viewModel.provider {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.caption2)
                            Text("\(p.providerName) / \(p.model)")
                                .font(.caption2)
                        }
                        .foregroundStyle(BsColor.brandAzure)
                    } else {
                        Text("未连接 AI")
                            .font(.caption2)
                            .foregroundStyle(BsColor.warning)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Provider warning

    private func providerWarning(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BsColor.warning)
                .font(.system(.body))
            VStack(alignment: .leading, spacing: 4) {
                Text("未配置 AI 供应商").font(.subheadline.weight(.semibold)).foregroundStyle(BsColor.warning)
                Text(msg).font(.caption).foregroundStyle(.orange.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BsColor.warning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(BsColor.warning.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Input form

    private var inputForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Platform picker
            VStack(alignment: .leading, spacing: 10) {
                label("选择平台")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(MediaPlatform.allCases) { p in
                        platformTile(p)
                    }
                }
            }

            // URL input
            VStack(alignment: .leading, spacing: 8) {
                label("内容链接", systemImage: "link")
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(BsColor.inkMuted)
                    TextField(
                        "粘贴\(viewModel.platform.label)分享文案或内容链接…",
                        text: $viewModel.inputUrl,
                        axis: .vertical
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .lineLimit(1...4)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(BsColor.inkMuted.opacity(0.08))
                )
            }

            // Image URLs
            VStack(alignment: .leading, spacing: 8) {
                label("截图链接（可选）", systemImage: "photo")
                TextEditor(text: $viewModel.imageUrlsText)
                    .frame(minHeight: 72)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(BsColor.inkMuted.opacity(0.08))
                    )
                Text("AI 会直接读取截图中的用户名、发布时间、点赞 / 收藏 / 评论 / 分享 / 播放等数据。每行一个链接或以逗号分隔。")
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkMuted)
            }

            if case let .error(msg) = viewModel.pageState, !msg.isEmpty {
                errorRow(msg)
            }

            HStack {
                Spacer()
                Button(action: { viewModel.submit() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                        Text("开始分析").font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [BsColor.brandAzure, BsColor.brandMint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .opacity(viewModel.canSubmit ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSubmit)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(BsColor.surfacePrimary)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    private func platformTile(_ p: MediaPlatform) -> some View {
        let selected = viewModel.platform == p
        return Button {
            viewModel.platform = p
        } label: {
            VStack(spacing: 6) {
                Image(systemName: p.icon)
                    .font(.system(.title3))
                Text(p.label)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? BsColor.brandAzure.opacity(0.08) : BsColor.inkMuted.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? BsColor.brandAzure : BsColor.inkMuted.opacity(0.18), lineWidth: selected ? 1.5 : 1)
                    )
            )
            .foregroundStyle(selected ? BsColor.brandAzure : BsColor.ink)
        }
        .buttonStyle(.plain)
    }

    private func label(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption.weight(.bold))
                .kerning(0.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(BsColor.inkMuted)
    }

    private func errorRow(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(BsColor.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("分析失败").font(.caption.weight(.semibold)).foregroundStyle(BsColor.danger)
                Text(msg).font(.caption).foregroundStyle(.red.opacity(0.8))
            }
            Spacer()
            Button {
                viewModel.reset()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.caption2)
                    Text("重试").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(BsColor.danger.opacity(0.12)))
                .foregroundStyle(BsColor.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(BsColor.danger.opacity(0.06)))
    }

    // MARK: - Progress section

    @ViewBuilder
    private var progressSection: some View {
        if let progress = viewModel.progress {
            VStack(alignment: .leading, spacing: 12) {
                // Phase pills
                HStack(spacing: 4) {
                    ForEach(Array(AIAnalysisPhase.ordered.enumerated()), id: \.element) { idx, phase in
                        phasePill(idx: idx, phase: phase, current: progress.phase)
                        if idx < AIAnalysisPhase.ordered.count - 1 {
                            Rectangle()
                                .fill(viewModel.phaseHistory.contains(phase) ? BsColor.success.opacity(0.4) : BsColor.inkMuted.opacity(0.2))
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(BsColor.inkMuted.opacity(0.15))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: viewModel.pageState == .done
                                        ? [.green, .green.opacity(0.7)]
                                        : [BsColor.brandAzure, BsColor.brandMint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(max(0, min(100, progress.percent))) / 100.0)
                            .animation(BsMotion.Anim.smooth, value: progress.percent)
                    }
                }
                .frame(height: 6)

                Text(progress.message).font(.caption2).foregroundStyle(BsColor.inkMuted)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(BsColor.surfacePrimary)
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 1)
            )
        }
    }

    private func phasePill(idx: Int, phase: AIAnalysisPhase, current: AIAnalysisPhase) -> some View {
        let history = viewModel.phaseHistory
        let isCurrent = (current == phase)
        let isComplete = history.contains(phase) && !isCurrent
        let isPending = !history.contains(phase)

        return HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isComplete ? BsColor.success : (isCurrent ? BsColor.brandAzure : BsColor.inkMuted.opacity(0.2)))
                    .frame(width: 18, height: 18)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(BsTypography.label)
                        .foregroundStyle(.white)
                } else {
                    Text("\(idx + 1)")
                        .font(BsTypography.label)
                        .foregroundStyle(isPending ? Color.secondary : Color.white)
                }
            }
            Text(phase.label)
                .font(BsTypography.meta.weight(isPending ? .regular : .medium))
                .foregroundStyle(isPending ? .secondary : BsColor.ink)
                .lineLimit(1)
        }
    }

    // MARK: - Scraped data

    @ViewBuilder
    private var scrapedDataSection: some View {
        if let data = viewModel.scrapedData, !data.isEmpty {
            DisclosureGroup {
                ScrollView(.vertical) {
                    Text(Self.prettyJson(data))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(BsColor.inkMuted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 260)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.caption)
                    Text("抓取数据预览").font(.caption.weight(.medium))
                }
                .foregroundStyle(BsColor.inkMuted)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(BsColor.surfacePrimary)
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 1)
            )
        }
    }

    private static func prettyJson(_ dict: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return "\(dict)"
        }
        return s
    }

    // MARK: - Report (intel card)

    @ViewBuilder
    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile").foregroundStyle(BsColor.brandAzure).font(.caption)
                Text("智能情报报告").font(.subheadline.weight(.semibold)).foregroundStyle(BsColor.ink)
                if viewModel.pageState == .streaming {
                    HStack(spacing: 4) {
                        Circle().fill(BsColor.brandAzure).frame(width: 6, height: 6)
                        Text("生成中").font(.caption2)
                    }
                    .foregroundStyle(BsColor.brandAzure)
                }
                Spacer(minLength: 0)
                if viewModel.pageState == .done, !viewModel.report.isEmpty {
                    Button {
                        UIPasteboard.general.string = viewModel.report
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc").font(.caption2)
                            Text("复制").font(.caption)
                        }
                        .foregroundStyle(BsColor.inkMuted)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            reportBody
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(BsColor.surfacePrimary)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }

    @ViewBuilder
    private var reportBody: some View {
        if viewModel.report.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.title3)
                    .foregroundStyle(BsColor.warning)
                Text("等待 AI 输出…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BsColor.warning)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            switch MediaAnalysisParser.parse(viewModel.report) {
            case .ok(let m):
                IntelReportView(result: m)
            case .failed(let reason):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(BsColor.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI 输出未匹配情报卡结构，显示原始内容：")
                                .font(.caption.weight(.semibold)).foregroundStyle(BsColor.warning)
                            Text(reason).font(.caption2).foregroundStyle(.orange.opacity(0.8))
                        }
                    }
                    Text(viewModel.report)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(BsColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(BsColor.inkMuted.opacity(0.06)))
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Spacer()
            if viewModel.pageState == .streaming {
                Button(role: .destructive) {
                    viewModel.stop()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle").font(.caption)
                        Text("停止生成").font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(BsColor.danger.opacity(0.5)))
                    .foregroundStyle(BsColor.danger)
                }
                .buttonStyle(.plain)
            }
            Button {
                viewModel.reset()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.caption)
                    Text("新的分析").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [BsColor.brandAzure, BsColor.brandMint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty hint

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(BsColor.brandAzure)
                .padding(12)
                .background(Circle().fill(BsColor.brandAzure.opacity(0.1)))
            Text("开始你的第一个分析")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BsColor.ink)
            Text("输入社交媒体链接 + 截图（可选），AI 会抽取平台 / 作者 / 互动数据 / 卖点 / 受众，并输出三档投流预算与 10 关键词的情报卡片。")
                .font(.caption)
                .foregroundStyle(BsColor.inkMuted)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                hintChip(icon: "globe", text: "支持 9 大平台")
                hintChip(icon: "photo", text: "多模态截图")
                hintChip(icon: "doc.text.magnifyingglass", text: "结构化情报卡")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: BsRadius.lg - 2).fill(BsColor.surfacePrimary.opacity(0.6)))
    }

    private func hintChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2)
        }
        .foregroundStyle(BsColor.inkMuted)
    }
}

// MARK: - Intel Report Subviews

private struct IntelReportView: View {
    let result: MediaAnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let summary = result.summary, !summary.isEmpty {
                summaryBanner(summary)
            }

            section(icon: "person.text.rectangle", title: "基础信息") {
                basicsGrid
            }

            section(icon: "chart.bar.fill", title: "互动数据") {
                metricsChart
            }

            section(icon: "target", title: "内容") {
                contentBlock
            }

            section(icon: "scale.3d", title: "评估") {
                evaluationBlock
            }

            section(icon: "dollarsign.circle.fill", title: "投流策略") {
                promotionBlock
            }

            section(icon: "key.fill", title: "关键词") {
                keywordsBlock
            }

            if let notes = result.otherNotes, !notes.isEmpty {
                section(icon: "note.text", title: "其他备注") {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(BsColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // ── Subviews ──

    private func summaryBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("一句话速览")
                .font(.caption2.weight(.bold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(BsColor.brandAzure)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(BsColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [BsColor.brandAzure.opacity(0.08), BsColor.brandAzure.opacity(0.06)],  // TODO(batch-3): evaluate .indigo → brandAzure
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(BsColor.brandAzure.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func section<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(.caption.weight(.bold)).kerning(0.6).textCase(.uppercase)
            }
            .foregroundStyle(BsColor.inkMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(BsColor.inkMuted.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(BsColor.inkMuted.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var basicsGrid: some View {
        let b = result.basics
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                infoCell(label: "平台", valueView: AnyView(
                    Text(b.platform.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(BsColor.brandAzure.opacity(0.1))  // TODO(batch-3): evaluate .indigo → brandAzure
                        )
                        .foregroundStyle(BsColor.brandAzure)  // TODO(batch-3): evaluate .indigo → brandAzure
                ))
                infoCell(label: "账号", text: b.authorHandle.map { "@\($0)" })
            }
            HStack(alignment: .top, spacing: 12) {
                infoCell(label: "发布时间", text: b.publishTime)
            }
            if let title = b.coverTitle {
                infoCell(label: "标题 / 封面文字", text: title, fullWidth: true)
            }
        }
    }

    private func infoCell(label: String, text: String?, fullWidth: Bool = false) -> some View {
        infoCell(label: label, valueView: AnyView(
            Text(text ?? "—")
                .font(.caption)
                .foregroundStyle(text == nil ? .secondary : BsColor.ink)
        ), fullWidth: fullWidth)
    }

    private func infoCell(label: String, valueView: AnyView, fullWidth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(BsTypography.label)
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(BsColor.inkMuted)
            valueView
        }
        .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
    }

    private struct MetricDatum: Identifiable {
        let id = UUID()
        let label: String
        let value: Int
        let emoji: String
    }

    private var metricsChart: some View {
        let m = result.metrics
        let data: [MetricDatum] = [
            .init(label: "点赞", value: m.likes ?? 0, emoji: "❤️"),
            .init(label: "收藏", value: m.collects ?? 0, emoji: "⭐"),
            .init(label: "评论", value: m.comments ?? 0, emoji: "💬"),
            .init(label: "分享", value: m.shares ?? 0, emoji: "🔄"),
            .init(label: "播放", value: m.plays ?? 0, emoji: "▶️"),
        ]
        let allZero = data.allSatisfy { $0.value == 0 }

        return VStack(alignment: .leading, spacing: 10) {
            if !allZero {
                Chart(data) { d in
                    BarMark(
                        x: .value("指标", d.label),
                        y: .value("数量", d.value)
                    )
                    .foregroundStyle(BsColor.brandAzure.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 140)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                }
            }

            HStack(spacing: 6) {
                ForEach(data) { d in
                    VStack(spacing: 4) {
                        Text("\(d.emoji) \(d.label)")
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                        Text(d.value > 0 ? Self.formatInt(d.value) : "—")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(d.value > 0 ? BsColor.ink : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(BsColor.inkMuted.opacity(0.05)))
                }
            }
        }
    }

    private static func formatInt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("主题").font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                Text(result.content.theme).font(.caption).foregroundStyle(BsColor.ink)
            }
            if !result.content.sellingPoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("核心卖点").font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                    ForEach(Array(result.content.sellingPoints.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•").foregroundStyle(BsColor.brandAzure)  // TODO(batch-3): evaluate .indigo → brandAzure
                            Text(item).font(.caption).foregroundStyle(BsColor.ink)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("目标受众").font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                Text(result.content.targetAudience).font(.caption).foregroundStyle(BsColor.ink)
            }
        }
    }

    private var evaluationBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            evaluationList(title: "✅ 优势", items: result.evaluation.strengths, color: BsColor.success)
            evaluationList(title: "🔧 改进", items: result.evaluation.improvements, color: BsColor.warning)
        }
    }

    private func evaluationList(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .kerning(0.4)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 4) {
                        Text("•").foregroundStyle(color)
                        Text(item).font(.caption).foregroundStyle(BsColor.ink)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(color.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var promotionBlock: some View {
        let p = result.paidPromotion
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                budgetTile(label: "低档", tier: p.budgetTiers.low, accent: BsColor.inkMuted)
                budgetTile(label: "中档", tier: p.budgetTiers.medium, accent: BsColor.brandAzure)  // TODO(batch-3): evaluate .indigo → brandAzure
                budgetTile(label: "高档", tier: p.budgetTiers.high, accent: BsColor.brandAzure)
            }
            if !p.audienceTargeting.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("定向人群").font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                    chipRow(items: p.audienceTargeting, color: BsColor.brandAzure)  // TODO(batch-3): evaluate .indigo → brandAzure
                }
            }
            if !p.bestTimeSlots.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最佳投放时段").font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                    chipRow(items: p.bestTimeSlots, color: BsColor.brandMint)
                }
            }
        }
    }

    private func budgetTile(label: String, tier: MediaAnalysisResult.PaidPromotion.Tier, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                Spacer()
                Text(tier.dailyCny).font(.caption.weight(.bold)).foregroundStyle(accent)
            }
            Text(tier.expected).font(.caption2).foregroundStyle(BsColor.inkMuted).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(accent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var keywordsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !result.keywords.brand.isEmpty {
                keywordGroup(title: "Brand · 品牌词", items: result.keywords.brand, color: BsColor.brandAzure)  // TODO(batch-3): evaluate .purple → brandAzure
            }
            if !result.keywords.category.isEmpty {
                keywordGroup(title: "Category · 品类词", items: result.keywords.category, color: BsColor.brandAzure)
            }
            if !result.keywords.longTail.isEmpty {
                keywordGroup(title: "Long-tail · 长尾词", items: result.keywords.longTail, color: BsColor.warning)
            }
        }
    }

    private func keywordGroup(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(BsTypography.label).textCase(.uppercase).foregroundStyle(color)
            chipRow(items: items, color: color, prefix: "#")
        }
    }

    private func chipRow(items: [String], color: Color, prefix: String = "") -> some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text("\(prefix)\(item)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
                            )
                    )
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - FlowLayout (SwiftUI Layout for chip wrapping)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var h: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                h += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        h += rowHeight
        return CGSize(width: width == .infinity ? rowWidth : width, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
