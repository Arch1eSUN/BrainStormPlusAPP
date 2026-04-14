//
//  ContentView.swift
//  Brainstorm+
//
//  Created by Archie Sun on 4/14/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    
    var body: some View {
        Group {
            if sessionManager.isLoadingSession {
                // Splash/Loading skeleton
                ZStack {
                    Color.Brand.background.ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.Brand.primary)
                        ProgressView()
                            .tint(Color.Brand.primary)
                    }
                }
                .transition(.opacity)
            } else if sessionManager.isAuthenticated {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                LoginView()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: sessionManager.isLoadingSession)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: sessionManager.isAuthenticated)
        .task {
            await sessionManager.checkSession()
        }
    }
}

#Preview {
    ContentView()
        .environment(SessionManager())
}
