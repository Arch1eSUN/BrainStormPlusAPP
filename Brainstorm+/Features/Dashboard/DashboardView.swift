import SwiftUI

// MARK: - Parity Backlog Placeholder
public struct ParityBacklogDestination: View {
    public let moduleName: String
    public let webRoute: String
    
    public init(moduleName: String, webRoute: String = "") {
        self.moduleName = moduleName
        self.webRoute = webRoute
    }
    
    public var body: some View {
        ZStack {
            Color.Brand.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 60))
                    .foregroundColor(Color.gray.opacity(0.5))
                
                Text(moduleName)
                    .font(.custom("Outfit-Bold", size: 24))
                    .foregroundColor(Color.Brand.text)
                
                Text("Web Route: \(webRoute.isEmpty ? "Unknown" : webRoute)")
                    .font(.custom("Inter-Medium", size: 14))
                    .foregroundColor(Color.gray)
                
                Text("This module is currently in the iOS migration backlog.\nIt will be addressed in subsequent development cycles.")
                    .font(.custom("Inter-Regular", size: 14))
                    .foregroundColor(Color.Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .navigationTitle(moduleName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var ns
    
    // Grid layout for quick actions
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // 1. ZY Office Background (Warm Tint)
                Color.Brand.background
                    .ignoresSafeArea()
                
                // 2. Subtle Glow Orbs (Mint Cyan + Azure Blue) for Web-Parity
                GeometryReader { proxy in
                    Circle()
                        .fill(Color.Brand.primary.opacity(0.08))
                        .frame(width: proxy.size.width * 1.5, height: proxy.size.width * 1.5)
                        .blur(radius: 80)
                        .offset(x: -proxy.size.width * 0.5, y: -proxy.size.height * 0.2)
                    
                    Circle()
                        .fill(Color.Brand.accent.opacity(0.06))
                        .frame(width: proxy.size.width * 1.2, height: proxy.size.width * 1.2)
                        .blur(radius: 60)
                        .offset(x: proxy.size.width * 0.3, y: proxy.size.height * 0.4)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                
                // 3. Scrollable Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        headerSection
                        timeCardSection
                        quickActionsSection
                        scheduleSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)      // Space under custom nav space
                    .padding(.bottom, 120)  // Space for Floating TabBar
                }
            }
            // Hiding native nav bar to use custom immersive header
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadData()
        }
        .refreshable {
            HapticManager.shared.trigger(.soft)
            await viewModel.loadData()
        }
    }
    
    // MARK: - Header Section
    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Avatar
            if viewModel.state == .loading {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 56, height: 56)
                    .shimmer()
                
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 120, height: 20)
                        .shimmer()
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 80, height: 16)
                        .shimmer()
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.Brand.primary.opacity(0.1))
                    
                    Text(String(viewModel.profile?.fullName?.prefix(1) ?? "U"))
                        .font(.custom("Outfit-Bold", size: 24))
                        .foregroundColor(Color.Brand.primary)
                }
                .frame(width: 56, height: 56)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome back,")
                        .font(.custom("Inter-Medium", size: 14))
                        .foregroundColor(Color.Brand.textSecondary)
                    
                    Text(viewModel.profile?.fullName ?? "Archie Sun")
                        .font(.custom("Outfit-Bold", size: 22))
                        .foregroundColor(Color.Brand.text)
                }
            }
            
            Spacer()
            
            // Notification Bell (Glassmorphism)
            NavigationLink(destination: ActionItemHelper.destination(for: .notifications)) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color.Brand.text)
                        .frame(width: 44, height: 44)
                        .zyGlassBackground(cornerRadius: 22, opacity: 0.8)
                    
                    // Unread dot
                    Circle()
                        .fill(Color.Brand.warning)
                        .frame(width: 10, height: 10)
                        .offset(x: -2, y: 2)
                }
            }
        }
    }
    
    // MARK: - Time Card Section (Geofence/Attendance)
    @ViewBuilder
    private var timeCardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Overview")
                    .font(.custom("Outfit-SemiBold", size: 18))
                    .foregroundColor(Color.Brand.text)
                
                Spacer()
                
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.custom("Inter-Medium", size: 14))
                    .foregroundColor(Color.Brand.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.Brand.primary.opacity(0.1))
                    .clipShape(Capsule())
            }
            
            // Azure Blue Gradient Card with premium mesh/glass feel
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Status")
                            .font(.custom("Inter-Medium", size: 14))
                            .foregroundColor(.white.opacity(0.85))
                        
                        Text("Checked In")
                            .font(.custom("Outfit-Bold", size: 28)) // High-end typography pop
                            .foregroundColor(.white)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.9))
                        Text("Shanghai HQ")
                            .font(.custom("Inter-Medium", size: 13))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    // Glassy capsule
                    .background(.ultraThinMaterial.opacity(0.4), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                }
                
                Spacer()
                
                // Exquisite tactile action button
                ZYMagneticButton(action: {
                    // Check in action
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 72, height: 72)
                            .shadow(color: .white.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(24)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [Color.Brand.primary, Color.Brand.primaryDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    // Inner subtle glow/texture
                    RadialGradient(
                        colors: [.white.opacity(0.15), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 200
                    )
                }
            )
            .zyCardStyle(cornerRadius: 32, shadowRadius: 24, shadowY: 12)
        }
    }
    
    // MARK: - Quick Actions Section
    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workflow Apps")
                .font(.custom("Outfit-SemiBold", size: 18))
                .foregroundColor(Color.Brand.text)
            
            // Refined Bento-style grid structure
            LazyVGrid(columns: columns, spacing: 16) {
                actionItem(module: .tasks, color: Color.Brand.primary)
                actionItem(module: .chat, titleOverride: "Team Chat", color: Color.Brand.accent)
                actionItem(module: .okr, color: .purple)
                actionItem(module: .knowledge, titleOverride: "Docs", color: .teal)
                actionItem(module: .leaves, color: Color.Brand.warning)
                actionItem(module: .announcements, titleOverride: "News", color: .indigo)

            }
        }
    }
    
    private func actionItem(module: AppModule, titleOverride: String? = nil, color: Color) -> some View {
        NavigationLink(destination: ActionItemHelper.destination(for: module)) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: module.iconName)
                        .font(.system(size: 20, weight: .regular)) // Pro-max: Lighter, non-filled icons
                        .foregroundColor(color)
                }
                
                Text(titleOverride ?? module.displayName)

                    .font(.custom("Inter-Medium", size: 12))
                    .foregroundColor(Color.Brand.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .zyCardStyle(cornerRadius: 24)
        }
    }
    
    // MARK: - Schedule Section
    @ViewBuilder
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Upcoming")
                    .font(.custom("Outfit-SemiBold", size: 18))
                    .foregroundColor(Color.Brand.text)
                
                Spacer()
                
                NavigationLink(destination: ScheduleView()) {
                    Text("See All")
                        .font(.custom("Inter-Medium", size: 14))
                        .foregroundColor(Color.Brand.primary)
                }
            }
            
            // Render upcoming events... currently mocked.
            // Using modern iOS tactile cards
            VStack(spacing: 12) {
                if viewModel.state == .loaded && viewModel.schedules.isEmpty {
                    emptyStateView
                } else {
                    // Premium Mock Card
                    ZYSpotlightCard {
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.Brand.primary)
                                .frame(width: 4)
                                .padding(.vertical, 8)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Weekly Sync: Mobile Team")
                                    .font(.custom("Outfit-Medium", size: 16))
                                    .foregroundColor(Color.Brand.text)
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 13))
                                    Text("10:00 AM - 11:30 AM")
                                        .font(.custom("Inter-Medium", size: 13))
                                }
                                .foregroundColor(Color.Brand.textSecondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.Brand.primary.opacity(0.04))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Color.Brand.primary.opacity(0.4))
            }
            
            Text("No upcoming events")
                .font(.custom("Outfit-Medium", size: 16))
                .foregroundColor(Color.Brand.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .zyCardStyle(cornerRadius: 24, shadowRadius: 5, shadowY: 2)
        .opacity(0.8)
    }
}

#Preview {
    DashboardView()
}
