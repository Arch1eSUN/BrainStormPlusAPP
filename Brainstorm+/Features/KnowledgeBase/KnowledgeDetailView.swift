import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch C.4c — Knowledge article detail.
//
// Previously `KnowledgeListView` pushed a placeholder `Text(...)` on
// row tap. This replaces that with a real detail screen that:
//   • Renders Markdown via SwiftUI's native `Text(.init(markdown))`
//     — the batch brief forbids pulling in a third-party renderer.
//   • Opens the file attachment (PDF / video / audio) via `Link`
//     when the row has `file_url` set, matching Web's
//     `<a href={file_url} target="_blank">` behavior in page.tsx.
//   • Wires the AI summary panel to the Web bridge route
//     `/api/mobile/knowledge/ai-summary` via the shared VM. When the
//     article has no cached summary, the panel shows a "生成 AI 摘要"
//     CTA; when cached, it shows the summary + generation date + a
//     "重新生成" button that forces regen.
// ══════════════════════════════════════════════════════════════════

public struct KnowledgeDetailView: View {
    public let articleId: UUID
    private let fallbackArticle: KnowledgeArticle
    @ObservedObject private var viewModel: KnowledgeListViewModel
    private let canEdit: Bool
    private let onEdit: (() -> Void)?
    private let onDelete: (() -> Void)?

    /// The live article — prefers the VM-backed copy (which gets patched
    /// after AI summary generation) and falls back to the snapshot
    /// passed at push time. This keeps the re-render cycle working
    /// without forcing the list view to round-trip through a binding.
    private var article: KnowledgeArticle {
        viewModel.article(withId: articleId) ?? fallbackArticle
    }

    public init(
        article: KnowledgeArticle,
        viewModel: KnowledgeListViewModel,
        canEdit: Bool = false,
        onEdit: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.articleId = article.id
        self.fallbackArticle = article
        self.viewModel = viewModel
        self.canEdit = canEdit
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.lg + 4) {
                // ─── Header ─────────────────────────────────────
                VStack(alignment: .leading, spacing: BsSpacing.sm + 2) {
                    if let category = article.category, !category.isEmpty {
                        Text(category)
                            .font(BsTypography.meta)
                            .padding(.horizontal, BsSpacing.sm)
                            .padding(.vertical, BsSpacing.xs)
                            .background(BsColor.brandAzure.opacity(0.15))
                            .foregroundStyle(BsColor.brandAzure)
                            .clipShape(Capsule())
                    }

                    Text(article.title)
                        .font(BsTypography.pageTitle)
                        .foregroundStyle(BsColor.ink)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: BsSpacing.md) {
                        if let updated = article.updatedAt ?? article.createdAt {
                            Label(updated.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                                .font(BsTypography.meta)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                        Label("\(article.views)", systemImage: "eye.fill")
                            .font(BsTypography.meta)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }

                // ─── File attachment ────────────────────────────
                if let urlString = article.fileUrl, let url = URL(string: urlString) {
                    Link(destination: url) {
                        HStack(spacing: BsSpacing.sm + 2) {
                            Image(systemName: "paperclip")
                                .font(.subheadline)
                                .foregroundStyle(BsColor.brandCoral)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("打开附件")
                                    .font(BsTypography.cardSubtitle)
                                    .foregroundStyle(BsColor.ink)
                                if let fileType = article.fileType {
                                    Text(fileType)
                                        .font(BsTypography.meta)
                                        .foregroundStyle(BsColor.inkMuted)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(BsColor.inkFaint)
                        }
                        .padding(BsSpacing.lg)
                        .background(BsColor.brandCoral.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                    }
                }

                // ─── Body (markdown) ────────────────────────────
                if let content = article.content, !content.isEmpty {
                    // SwiftUI's Text(.init(...)) auto-parses basic
                    // Markdown (bold/italic/links/inline code). Block-
                    // level markdown (headings, lists, code fences)
                    // renders as-is — Web's Markdown rendering is
                    // richer but the brief explicitly prohibits
                    // pulling in a third-party parser.
                    Text(.init(content))
                        .font(BsTypography.body)
                        .foregroundStyle(BsColor.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if article.fileUrl == nil {
                    Text("（无正文）")
                        .font(BsTypography.body)
                        .foregroundStyle(BsColor.inkFaint)
                }

                // ─── AI summary (glass — "AI 生成" 折射质感) ──────
                aiSummarySection

                // ─── Admin actions ──────────────────────────────
                if canEdit {
                    HStack(spacing: BsSpacing.md) {
                        if let onEdit {
                            Button {
                                onEdit()
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .buttonStyle(BsSecondaryButtonStyle(size: .medium))
                        }
                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .buttonStyle(BsDestructiveButtonStyle(size: .medium))
                        }
                    }
                }
            }
            .padding(BsSpacing.lg)
        }
        .background(BsColor.pageBackground)
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var aiSummarySection: some View {
        let current = article
        let isGenerating = viewModel.generatingSummaryIds.contains(current.id)

        // BsCard(glass) — iOS 26 真 Liquid Glass，给 "AI 生成" 区提供折射质感
        BsCard(variant: .glass, padding: .medium) {
            VStack(alignment: .leading, spacing: BsSpacing.sm + 2) {
                HStack(spacing: BsSpacing.xs + 2) {
                    Image(systemName: "sparkles")
                    Text("AI 摘要")
                        .font(BsTypography.label)
                    Spacer()
                    if isGenerating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.purple)
                    }
                }
                .foregroundStyle(.purple)

                if let summary = current.aiSummary, !summary.isEmpty {
                    Text(summary)
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: BsSpacing.sm) {
                        if let at = current.aiSummaryAt {
                            Text("已生成于 \(at.formatted(date: .abbreviated, time: .shortened))")
                                .font(BsTypography.meta)
                                .foregroundStyle(BsColor.inkFaint)
                        }
                        if let model = current.aiSummaryModel {
                            Text("· \(model)")
                                .font(BsTypography.meta)
                                .foregroundStyle(BsColor.inkFaint)
                        }
                        Spacer()
                        Button {
                            Task {
                                await viewModel.generateAISummary(
                                    for: current,
                                    forceRegenerate: true
                                )
                            }
                        } label: {
                            Label("重新生成", systemImage: "arrow.triangle.2.circlepath")
                                .font(BsTypography.captionSmall)
                        }
                        .buttonStyle(.borderless)
                        .tint(.purple)
                        .disabled(isGenerating)
                    }
                } else {
                    Text("尚未生成 AI 摘要。点击下方按钮，由服务端的 askAI 为你提炼 3-5 条要点。")
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.inkMuted)

                    Button {
                        Task {
                            await viewModel.generateAISummary(
                                for: current,
                                forceRegenerate: false
                            )
                        }
                    } label: {
                        HStack(spacing: BsSpacing.xs + 2) {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.white)
                                Text("生成中...")
                            } else {
                                Image(systemName: "sparkles")
                                Text("生成 AI 摘要")
                            }
                        }
                        .font(BsTypography.cardSubtitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BsSpacing.sm + 2)
                        .background(Color.purple.opacity(isGenerating ? 0.5 : 1))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md - 2, style: .continuous))
                    }
                    .disabled(isGenerating)
                }

                if let err = viewModel.errorMessage, err.contains("AI 摘要") {
                    Text(err)
                        .font(BsTypography.meta)
                        .foregroundStyle(BsColor.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
