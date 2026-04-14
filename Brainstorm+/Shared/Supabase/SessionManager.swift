import SwiftUI

@Observable
public final class SessionManager {
    public var isAuthenticated: Bool = false
    
    public init() {}
    
    public func login() {
        // Mock async login until Supabase SDK is fully integrated
        withAnimation {
            isAuthenticated = true
        }
    }
    
    public func logout() {
        withAnimation {
            isAuthenticated = false
        }
    }
}
