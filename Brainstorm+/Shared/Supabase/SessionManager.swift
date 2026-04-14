import SwiftUI
import Supabase

@MainActor
@Observable
public final class SessionManager {
    public var isAuthenticated: Bool = false
    public var isLoadingSession: Bool = true
    
    public init() {}
    
    /// Checks for an existing session on app launch
    public func checkSession() async {
        do {
            _ = try await supabase.auth.session
            withAnimation {
                self.isAuthenticated = true
                self.isLoadingSession = false
            }
        } catch {
            withAnimation {
                self.isAuthenticated = false
                self.isLoadingSession = false
            }
        }
    }
    
    public func login(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(email: email, password: password)
        withAnimation {
            self.isAuthenticated = true
        }
    }
    
    public func logout() async throws {
        try await supabase.auth.signOut()
        withAnimation {
            self.isAuthenticated = false
        }
    }
}
