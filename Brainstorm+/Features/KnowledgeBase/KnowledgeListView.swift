import SwiftUI
import Combine

public struct KnowledgeListView: View {
    @StateObject private var viewModel: KnowledgeListViewModel
    
    public init(viewModel: KnowledgeListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.articles.isEmpty {
                    ProgressView()
                } else if viewModel.articles.isEmpty {
                    ContentUnavailableView("No Articles", systemImage: "book.closed", description: Text("No matching articles found in the knowledge base."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.articles) { article in
                                NavigationLink(destination: Text("Article Content: \(article.title)").padding()) {
                                    KnowledgeCardView(article: article)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Knowledge Base")
            .refreshable {
                await viewModel.fetchArticles()
            }
            .task {
                await viewModel.fetchArticles()
            }
        }
    }
}
