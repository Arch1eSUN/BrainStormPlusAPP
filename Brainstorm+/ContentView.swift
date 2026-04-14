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
            if sessionManager.isAuthenticated {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                LoginView()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: sessionManager.isAuthenticated)
    }
}

#Preview {
    ContentView()
        .environment(SessionManager())
}
