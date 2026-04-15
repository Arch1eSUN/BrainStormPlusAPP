import Foundation
import Combine
import Supabase

@MainActor
public class ChatListViewModel: ObservableObject {
    @Published public var channels: [ChatChannel] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let client: SupabaseClient
    
    public init(client: SupabaseClient) {
        self.client = client
    }
    
    public func fetchChannels() async {
        isLoading = true
        errorMessage = nil
        do {
            self.channels = try await client
                .from("chat_channels")
                .select()
                .order("last_message_at", ascending: false)
                .execute()
                .value
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
