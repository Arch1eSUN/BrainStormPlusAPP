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
                // 跟 @main 入口 BrainStormApp 用同一个 SplashView,
                // 保证启动态的视觉一致性(真 BrandLogo + 呼吸动画 + 3 dots)
                SplashView()
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
