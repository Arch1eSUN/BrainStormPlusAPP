import Foundation
import Combine
import Supabase

@MainActor
public class KnowledgeListViewModel: ObservableObject {
    @Published public var articles: [KnowledgeArticle] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let client: SupabaseClient
    
    public init(client: SupabaseClient) {
        self.client = client
    }
    
    public func fetchArticles() async {
        isLoading = true
        errorMessage = nil
        do {
            self.articles = try await client
                .from("knowledge_articles")
                .select()
                .eq("status", value: "published")
                .order("views", ascending: false)
                .execute()
                .value
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
