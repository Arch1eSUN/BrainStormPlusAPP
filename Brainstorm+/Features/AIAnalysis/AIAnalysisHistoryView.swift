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
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "暂无历史记录",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("完成第一个媒体分析后，历史会出现在这里。")
                )
            } else {
                listView
            }
        }
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

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.md) {
                // Meta
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

                // Report (try parsing into IntelReport-style schema; fallback to raw)
                BsContentCard(padding: .small) {
                    reportContent
                }
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.vertical, BsSpacing.md)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
        .navigationTitle("分析详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var reportContent: some View {
        if let raw = item.aiRawResponse, !raw.isEmpty {
            switch MediaAnalysisParser.parse(raw) {
            case .ok(let parsed):
                // Reuse the same Intel report renderer used by the live view.
                // Note: IntelReportView is private to AIAnalysisView.swift —
                // we render a compact text fallback here to stay decoupled
                // (and avoid circular dependencies). The cleanest UX-equivalent
                // for read-only history is the parsed JSON pretty-print.
                Text(prettyJson(parsed))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(BsColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            case .failed:
                Text(raw)
                    .font(.caption)
                    .foregroundStyle(BsColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        } else if let err = item.errorMessage {
            Text(err)
                .font(.caption)
                .foregroundStyle(BsColor.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("暂无报告内容")
                .font(.caption)
                .foregroundStyle(BsColor.inkMuted)
        }
    }

    private func prettyJson<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "\(value)"
    }
}
