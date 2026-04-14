import SwiftUI
import Supabase

@main
struct BrainStormApp: App {
    @StateObject private var authState = AuthStateManager()
    @StateObject private var realtimeSync = RealtimeSyncManager.shared
    
    var body: some Scene {
        WindowGroup {
            if authState.isAuthenticated {
                DashboardView()
                    .environmentObject(authState)
                    .environmentObject(realtimeSync)
            } else {
                LoginView()
                    .environmentObject(authState)
            }
        }
    }
}

// MARK: - Auth State Mock
@MainActor
class AuthStateManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User? = nil
    
    init() {
        Task {
            // Check existing session
            if let session = try? await supabase.auth.session {
                self.isAuthenticated = true
                self.currentUser = session.user
            }
            
            // Listen to auth changes
            for await authEvent in supabase.auth.authStateChanges {
                if authEvent.event == .signedIn {
                    self.isAuthenticated = true
                    self.currentUser = authEvent.session?.user
                } else if authEvent.event == .signedOut {
                    self.isAuthenticated = false
                    self.currentUser = nil
                }
            }
        }
    }
}
