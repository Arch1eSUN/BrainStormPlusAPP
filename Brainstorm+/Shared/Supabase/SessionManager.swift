import SwiftUI
import Supabase

@MainActor
@Observable
public final class SessionManager {
    public var isAuthenticated: Bool = false
    public var isLoadingSession: Bool = true
    
    // Add current profile cache for fast RBAC checks
    public var currentProfile: Profile?
    
    public init() {}
    
    /// Checks for an existing session on app launch
    public func checkSession() async {
        do {
            _ = try await supabase.auth.session
            await fetchProfile()
            withAnimation {
                self.isAuthenticated = true
                self.isLoadingSession = false
            }
        } catch {
            withAnimation {
                self.isAuthenticated = false
                self.isLoadingSession = false
                self.currentProfile = nil
            }
        }
    }
    
    private func fetchProfile() async {
        do {
            let session = try await supabase.auth.session
            let userId = session.user.id
            let profile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            
            withAnimation {
                self.currentProfile = profile
            }
        } catch {
            print("SessionManager: Failed to fetch profile - \(error)")
        }
    }
    
    public func login(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(email: email, password: password)
        await fetchProfile()
        withAnimation {
            self.isAuthenticated = true
        }
    }
    
    public func logout() async throws {
        try await supabase.auth.signOut()
        withAnimation {
            self.isAuthenticated = false
            self.currentProfile = nil
        }
    }
}
