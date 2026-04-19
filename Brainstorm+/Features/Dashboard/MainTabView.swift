import SwiftUI

struct MainTabView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var selectedTab = 0

    // Compute effective capabilities
    private var hasCopilotAccess: Bool {
        guard let profile = sessionManager.currentProfile else { return false }
        let caps = RBACManager.shared.getEffectiveCapabilities(for: profile)
        return RBACManager.shared.hasCapability(.ai_chatbot_access, in: caps)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Content Area
            TabView(selection: $selectedTab) {
                // Real Dashboard Tab
                NavigationStack {
                    DashboardView()
                        .navigationTitle("Dashboard")
                        .navigationBarHidden(true)
                }
                .tag(0)
                
                // Schedule Tab Placeholder
                NavigationStack {
                    ScheduleView()
                        .navigationBarHidden(true)
                }
                .tag(1)
                
                // Copilot Tab Placeholder (Protected by RBAC)
                NavigationStack {
                    ZStack {
                        if hasCopilotAccess {
                            AICopilotView()
                        } else {
                            Color.Brand.background.ignoresSafeArea()
                            
                            VStack(spacing: 16) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(Color.gray.opacity(0.5))
                                
                                Text("BrainStorm+ Copilot (Coming Soon)")
                                    .font(.custom("Outfit-Bold", size: 20))
                                    .foregroundStyle(Color.Brand.text)
                                
                                Text("This feature is currently locked or under development. It will require the AI Chatbot Access capability.")
                                    .font(.custom("Inter-Medium", size: 14))
                                    .foregroundStyle(Color.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                        }
                    }
                    .navigationTitle("Copilot")
                }
                .tag(2)
                
                // Settings Tab
                NavigationStack {
                    SettingsView()
                        .navigationBarHidden(true)
                }
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never)) // We handle the tab selection manually
            
            // Custom Liquid Glass Floating Tab Bar
            FloatingTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Global attempt to alter nav bar appearance (UIKit)
        .onAppear {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(Color.Brand.background).withAlphaComponent(0.85)
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            appearance.shadowColor = .clear // Remove bottom border line
            
            // Note: In real app, load custom fonts for Large Title and inline title here
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// MARK: - Floating Tab Bar Component
struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    
    let tabs = [
        (icon: "rectangle.grid.2x2.fill", title: "Dashboard"),
        (icon: "calendar.badge.clock", title: "Schedule"),
        (icon: "brain.head.profile", title: "Copilot"),
        (icon: "gearshape.fill", title: "Settings")
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                GeometryReader { proxy in
                    let isSelected = selectedTab == index
                    
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 20, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? Color.Brand.primary : Color.gray.opacity(0.6))
                            .scaleEffect(isSelected ? 1.1 : 1.0)
                        
                        if isSelected {
                            Circle()
                                .fill(Color.Brand.primary) // Updated from accent/teal to primary Azure Blue
                                .frame(width: 4, height: 4)
                        } else {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle()) // makes entire area tappable
                    .onTapGesture {
                        if selectedTab != index {
                            HapticManager.shared.trigger(.soft)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = index
                            }
                        }
                    }
                }
                .frame(height: 56)
            }
        }
        // Liquid Glass effect
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.6))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 15, x: 0, y: 10)
        )
    }
}

#Preview {
    MainTabView()
}
