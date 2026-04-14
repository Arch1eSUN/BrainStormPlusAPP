import Foundation
import Supabase

@Observable
public final class SettingsViewModel {
    public var profile: Profile?
    public var isLoading = false
    public var errorMessage: String?
    
    @MainActor
    public func loadProfile() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let session = try await supabase.auth.session
            let currentUser = session.user
            
            let fetchedProfile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: currentUser.id)
                .single()
                .execute()
                .value
            
            self.profile = fetchedProfile
        } catch {
            self.errorMessage = "Failed to load profile: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    @MainActor
    public func signOut() async {
        do {
            try await supabase.auth.signOut()
            SessionManager.shared.isAuthenticated = false
        } catch {
            print("Error signing out: \(error)")
        }
    }
}
