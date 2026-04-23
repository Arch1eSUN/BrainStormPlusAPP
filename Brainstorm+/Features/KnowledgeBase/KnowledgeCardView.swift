import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch C.4c — Knowledge card, updated for the CRUD/file-upload flow.
//
// Matches the grid tile in
// `BrainStorm+-Web/src/app/dashboard/knowledge/page.tsx` (≈ L355-L475):
//   • category pill (top-left)
//   • views counter (top-right)
//   • title (link-styled when there's a file, plain otherwise)
//   • truncated body preview
//   • file-attachment icon + file-type subtitle when `file_url` is set
//
// Author footer is intentionally out of scope for this card —
// author avatar is not yet on iOS (no join into profiles in the VM
// fetch). The AI summary lives in the detail view's panel (matches
// Web, which hides the summary inside a click-to-expand panel rather
// than leaking it onto every grid tile).
// ══════════════════════════════════════════════════════════════════

public struct KnowledgeCardView: View {
    public let article: KnowledgeArticle

    public init(article: KnowledgeArticle) {
        self.article = article
    }

    public var body: some View {
        BsCard(variant: .flat, padding: .medium) {
            VStack(alignment: .leading, spacing: BsSpacing.md) {
                HStack {
                    if let category = article.category, !category.isEmpty {
                        Text(category)
                            .font(BsTypography.meta)
                            .padding(.horizontal, BsSpacing.sm)
                            .padding(.vertical, BsSpacing.xs)
                            .background(BsColor.brandAzure.opacity(0.15))
                            .foregroundStyle(BsColor.brandAzure)
                            .clipShape(Capsule())
                    }

                    if article.fileUrl != nil {
                        Label("附件", systemImage: "paperclip")
                            .labelStyle(.titleAndIcon)
                            .font(BsTypography.meta)
                            .foregroundStyle(BsColor.brandCoral)
                            .padding(.horizontal, BsSpacing.xs + 2)
                            .padding(.vertical, 2)
                            .background(BsColor.brandCoral.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    HStack(spacing: BsSpacing.xs) {
                        Image(systemName: "eye.fill")
                            .font(.caption2)
                        Text("\(article.views)")
                            .font(BsTypography.meta)
                    }
                    .foregroundStyle(BsColor.inkMuted)
                }

                Text(article.title)
                    .font(BsTypography.cardTitle)
                    .foregroundStyle(BsColor.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                if let content = article.content, !content.isEmpty {
                    Text(content)
                        .font(BsTypography.bodySmall)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                } else if let fileType = article.fileType {
                    Text(fileType)
                        .font(BsTypography.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }

                if let updatedAt = article.updatedAt ?? article.createdAt {
                    Text(updatedAt, style: .date)
                        .font(BsTypography.meta)
                        .foregroundStyle(BsColor.inkFaint)
                }
            }
        }
    }
}
