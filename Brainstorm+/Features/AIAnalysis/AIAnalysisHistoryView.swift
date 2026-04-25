import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// AIAnalysisHistoryView — Round 50 fix #2 (iOS side)
//
// Reads `ai_analysis_history` directly via supabase-swift; RLS owner-only
// scopes results. List shows thumbnail + title + platform pill + relative
// time + status. Tap → push read-only detail view; long-press → delete.
//
// Design system constraint: do not modify Shared/DesignSystem — uses
// existing BsColor / BsSpacing / BsTypography / BsRadius / BsContentCard
// primitives only.
// ══════════════════════════════════════════════════════════════════

public struct AIAnalysisHistoryView: View {
    @StateObject private var viewModel: AIAnalysisHistoryViewModel
    @State private var pendingDelete: AIAnalysisHistoryItem? = nil

    @MainActor
    public init() {
        _viewModel = StateObject(wrappedValue: AIAnalysisHistoryViewModel())
    }

    public var body: some View {
        // Iter 7 §C.1 — skeleton-first: 用 bsLoadingState 把 loading/stale/empty/error
        // 四态合并到 design system modifier,List 在所有状态下保持挂载,
        // 不再频繁 swap subview。
        listView
            .bsLoadingState(BsLoadingState.derive(
                isLoading: viewModel.isLoading,
                hasItems: !viewModel.items.isEmpty,
                errorMessage: viewModel.errorMessage,
                emptySystemImage: "clock.arrow.circlepath",
                emptyTitle: "暂无历史记录",
                emptyDescription: "完成第一个媒体分析后，历史会出现在这里。"
            ))
            .animation(.smooth(duration: 0.25), value: viewModel.items.count)
            .navigationTitle("分析历史")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.reload() }
        .confirmationDialog(
            "删除该分析？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("删除", role: .destructive) {
                Task { await viewModel.delete(item) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("此操作无法撤销。")
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: BsSpacing.smd) {
                ForEach(viewModel.items) { item in
                    NavigationLink {
                        AIAnalysisHistoryDetailView(item: item)
                    } label: {
                        AIAnalysisHistoryRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDelete = item
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .onAppear {
                        if item.id == viewModel.items.last?.id {
                            Task { await viewModel.loadMoreIfNeeded() }
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView().padding(.vertical, BsSpacing.md)
                }
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.md)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
    }
}

// ── Row ────────────────────────────────────────────────────────────

private struct AIAnalysisHistoryRow: View {
    let item: AIAnalysisHistoryItem

    var body: some View {
        BsContentCard(padding: .small) {
            HStack(alignment: .top, spacing: BsSpacing.smd) {
                thumbnail
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: BsSpacing.xs) {
                    HStack(spacing: BsSpacing.xs) {
                        Text(item.platformLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, BsSpacing.xs + 2)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: BsRadius.xs, style: .continuous)
                                    .fill(BsColor.brandAzure.opacity(0.1))
                            )
                            .foregroundStyle(BsColor.brandAzure)

                        statusPill

                        Spacer(minLength: 0)

                        Text(item.relativeTimeString)
                            .font(.caption2)
                            .foregroundStyle(BsColor.inkMuted)
                    }

                    Text(item.displayTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BsColor.ink)
                        .lineLimit(2)

                    if let url = item.sourceUrl {
                        Text(url)
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let urlString = item.coverImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [BsColor.brandAzure.opacity(0.2), BsColor.brandMint.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: item.platformIcon)
                .font(.title3)
                .foregroundStyle(BsColor.brandAzure)
        }
    }

    private var statusPill: some View {
        let (label, color): (String, Color) = {
            switch item.status {
            case "completed": return ("已完成", BsColor.success)
            case "failed":    return ("失败", BsColor.danger)
            case "partial":   return ("部分", BsColor.warning)
            default:          return (item.status, BsColor.inkMuted)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, BsSpacing.xs + 2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.xs, style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .foregroundStyle(color)
    }
}

// ── Detail (read-only) ────────────────────────────────────────────

public struct AIAnalysisHistoryDetailView: View {
    let item: AIAnalysisHistoryItem
    /// Optional retry callback — wired by the parent so we can pop back to
    /// the analyze view with the source URL prefilled. When nil the CTA
    /// degrades to a plain disabled affordance.
    var onRetry: ((AIAnalysisHistoryItem) -> Void)? = nil

    public init(item: AIAnalysisHistoryItem, onRetry: ((AIAnalysisHistoryItem) -> Void)? = nil) {
        self.item = item
        self.onRetry = onRetry
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.md) {
                metaCard

                // Status banner: failed / partial — schema-card layout for completed.
                switch item.status {
                case "failed":
                    failedBanner
                case "partial":
                    partialBanner
                    reportCard
                default:
                    reportCard
                }

                metadataFooter
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.md)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
        .navigationTitle("分析详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    // ── Meta header ──
    private var metaCard: some View {
        BsContentCard(padding: .small) {
            VStack(alignment: .leading, spacing: BsSpacing.xs) {
                HStack(spacing: BsSpacing.xs) {
                    Text(item.platformLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, BsSpacing.sm)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: BsRadius.xs, style: .continuous)
                                .fill(BsColor.brandAzure.opacity(0.1))
                        )
                        .foregroundStyle(BsColor.brandAzure)
                    if let m = item.modelUsed {
                        Text(m)
                            .font(.caption2)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    Spacer(minLength: 0)
                    Text(item.relativeTimeString)
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkMuted)
                }
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BsColor.ink)
                if let src = item.sourceUrl, let url = URL(string: src) {
                    Link(destination: url) {
                        HStack(spacing: BsSpacing.xs) {
                            Image(systemName: "link").font(.caption2)
                            Text(src).font(.caption2).lineLimit(1)
                        }
                        .foregroundStyle(BsColor.brandAzure)
                    }
                }
            }
        }
    }

    // ── Failed banner with retry CTA ──
    private var failedBanner: some View {
        BsContentCard(padding: .small) {
            VStack(alignment: .leading, spacing: BsSpacing.smd) {
                HStack(alignment: .top, spacing: BsSpacing.smd) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BsColor.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("分析失败")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BsColor.danger)
                        Text(item.errorMessage ?? "出了点小问题，可在 设置 → 反馈 联系我们")
                            .font(.caption)
                            .foregroundStyle(BsColor.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if item.sourceUrl != nil, let onRetry {
                    Button {
                        onRetry(item)
                    } label: {
                        HStack(spacing: BsSpacing.xs) {
                            Image(systemName: "arrow.clockwise").font(.caption2)
                            Text("重新分析").font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, BsSpacing.smd)
                        .padding(.vertical, BsSpacing.xs + 2)
                        .background(
                            RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous)
                                .fill(BsColor.danger.opacity(0.1))
                        )
                        .foregroundStyle(BsColor.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ── Partial banner (still shows whatever schema parsed) ──
    private var partialBanner: some View {
        BsContentCard(padding: .small) {
            HStack(alignment: .top, spacing: BsSpacing.smd) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(BsColor.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("部分数据未抓取")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BsColor.warning)
                    Text("已根据可用数据生成情报卡，可能缺失互动指标或封面文案。")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // ── Report card — reuses the live IntelReportView ──
    @ViewBuilder
    private var reportCard: some View {
        if let raw = item.aiRawResponse, !raw.isEmpty {
            switch MediaAnalysisParser.parse(raw) {
            case .ok(let parsed):
                IntelReportView(result: parsed)
            case .failed:
                BsContentCard(padding: .small) {
                    VStack(alignment: .leading, spacing: BsSpacing.xs) {
                        Text("AI 输出未匹配情报卡结构，显示原始内容")
                            .font(BsTypography.captionSmall.weight(.semibold))
                            .foregroundStyle(BsColor.warning)
                        Text(raw)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(BsColor.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
        } else {
            BsContentCard(padding: .small) {
                Text("暂无报告内容")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // ── Metadata footer (created_at / duration / model) ──
    private var metadataFooter: some View {
        let durationText: String? = item.durationMs.map { ms in
            let s = Double(ms) / 1000.0
            return String(format: "%.1fs", s)
        }
        return BsContentCard(padding: .small) {
            HStack(spacing: BsSpacing.md) {
                Label(formattedCreatedAt, systemImage: "clock")
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
                if let durationText {
                    Label(durationText, systemImage: "timer")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
                if let model = item.modelUsed {
                    Label(model, systemImage: "brain")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var formattedCreatedAt: String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoFormatter.date(from: item.createdAt)
            ?? ISO8601DateFormatter().date(from: item.createdAt)
        guard let date else { return item.createdAt }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}
