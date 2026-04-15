import Foundation
import Combine
import Supabase

public struct AppEnvironment {
    public static let supabaseURL = URL(string: "https://scaicmjprkqlkpagbnbh.supabase.co")!
    public static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNjYWljbWpwcmtxbGtwYWdibmJoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyODU1MDgsImV4cCI6MjA4OTg2MTUwOH0.6K6yKMkkH9D-XsZmMdBk4tRsl5X6b3V4uVmYLP_lkaQ"
}

public let supabase = SupabaseClient(
    supabaseURL: AppEnvironment.supabaseURL,
    supabaseKey: AppEnvironment.supabaseAnonKey
)

@MainActor
public class RealtimeSyncManager: ObservableObject {
    public static let shared = RealtimeSyncManager()
    
    @Published public var isConnected = false
    
    private var channels: [String: RealtimeChannelV2] = [:]
    
    private init() {}
    
    /// Listens to global changes for the given table.
    /// In a real usage, you'd filter by user_id or specific row ID depending on RLS.
    public func subscribeToTableChanges(tableName: String, callback: @escaping (Any) -> Void) async {
        guard channels[tableName] == nil else { return }
        
        let channel = supabase.channel(tableName)
        
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: tableName
        )
        
        self.channels[tableName] = channel
        
        await channel.subscribe()
        DispatchQueue.main.async {
            self.isConnected = true
        }
        
        Task {
            for await change in changes {
                // Here we pass the change to the main app loop
                DispatchQueue.main.async {
                    callback(change)
                }
            }
        }
    }
    
    public func unsubscribe(tableName: String) async {
        guard let channel = channels[tableName] else { return }
        await channel.unsubscribe()
        channels.removeValue(forKey: tableName)
    }
}
