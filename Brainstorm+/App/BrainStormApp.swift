import SwiftUI
import Combine
import Supabase

@main
struct BrainStormApp: App {
    @State private var sessionManager = SessionManager()
    @StateObject private var realtimeSync = RealtimeSyncManager.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
                if sessionManager.isLoadingSession {
                    SplashView()
                } else if sessionManager.isAuthenticated {
                    MainTabView()
                        .environment(sessionManager)
                        .environmentObject(realtimeSync)
                } else {
                    LoginView()
                        .environment(sessionManager)
                }
            }
            .task {
                await sessionManager.checkSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SupabaseAuthChange"))) { notification in
                // Global fallback for auth states out of band
                Task {
                    await sessionManager.checkSession()
                }
            }
        }
    }
}

// Simple splash view while checking session
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.Brand.background.ignoresSafeArea()
            VStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Color.Brand.primary)
                Text("BrainStorm+")
                    .font(.custom("Outfit-Bold", size: 32))
                    .foregroundStyle(Color.Brand.text)
                    .padding(.top, 16)
            }
        }
    }
}
