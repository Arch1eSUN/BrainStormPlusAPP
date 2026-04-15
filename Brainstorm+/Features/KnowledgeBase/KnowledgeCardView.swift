import SwiftUI

public struct KnowledgeCardView: View {
    public let article: KnowledgeArticle
    
    public init(article: KnowledgeArticle) {
        self.article = article
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let category = article.category {
                    Text(category.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                    Text("\(article.views)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
            }
            
            Text(article.title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(2)
            
            Text(article.content)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
