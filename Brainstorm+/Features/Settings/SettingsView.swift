import SwiftUI
import Supabase

public struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var showingSignOutAlert = false
    @Environment(SessionManager.self) private var sessionManager
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.Brand.background
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        // Spacer for custom header
                        Spacer().frame(height: 80)
                        
                        headerSection
                        generalSection
                        supportSection
                        signOutSection
                        
                        // Tab bar spacing
                        Spacer().frame(height: 100)
                    }
                    .padding(.horizontal, 24)
                }
                
                // Custom Immersive Header
                VStack {
                    customHeader
                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.loadProfile()
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    HapticManager.shared.trigger(.medium)
                    Task {
                        await viewModel.signOut(sessionManager: sessionManager)
                    }
                }
            } message: {
                Text("Are you sure you want to sign out from BrainStorm+?")
            }
        }
    }
    
    @ViewBuilder
    private var customHeader: some View {
        HStack {
            Text("Settings")
                .font(.custom("Outfit-Bold", size: 28))
                .foregroundColor(Color.Brand.text)
            
            Spacer()
            
            // Decorative settings cog
            ZStack {
                Circle()
                    .fill(Color.Brand.primary.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.Brand.primary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.4))
                .padding(.top, -1),
            alignment: .top
        )
    }
    
    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.Brand.accent.opacity(0.2))
                    .frame(width: 88, height: 88)
                
                Text(String(viewModel.profile?.fullName?.prefix(1) ?? "U"))
                    .font(.custom("Outfit-Bold", size: 36))
                    .foregroundColor(Color.Brand.primary)
            }
            .shadow(color: Color.Brand.accent.opacity(0.3), radius: 12, x: 0, y: 6)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.profile?.fullName ?? "User")
                    .font(.custom("Outfit-Bold", size: 24))
                    .foregroundColor(Color.Brand.text)
                
                Text(viewModel.profile?.role?.capitalized ?? "Team Member")
                    .font(.custom("Inter-Medium", size: 14))
                    .foregroundColor(Color.Brand.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.Brand.primary.opacity(0.1))
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
    }
    
    @ViewBuilder
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.custom("Outfit-SemiBold", size: 14))
                .foregroundColor(Color.Brand.textSecondary)
                .textCase(.uppercase)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                SettingsRowView(icon: "bell.badge.fill", iconColor: .blue, title: "Notifications", showChevron: true)
                Divider().background(Color.gray.opacity(0.1)).padding(.leading, 64)
                SettingsRowView(icon: "lock.shield.fill", iconColor: .green, title: "Privacy & Security", showChevron: true)
                Divider().background(Color.gray.opacity(0.1)).padding(.leading, 64)
                SettingsRowView(icon: "paintpalette.fill", iconColor: .purple, title: "Appearance", showChevron: true)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
        }
    }
    
    @ViewBuilder
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Support")
                .font(.custom("Outfit-SemiBold", size: 14))
                .foregroundColor(Color.Brand.textSecondary)
                .textCase(.uppercase)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                SettingsRowView(icon: "questionmark.circle.fill", iconColor: Color.Brand.accent, title: "Help Center", showChevron: true)
                Divider().background(Color.gray.opacity(0.1)).padding(.leading, 64)
                SettingsRowView(icon: "doc.text.fill", iconColor: .gray, title: "Terms of Service", showChevron: true)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
        }
    }
    
    @ViewBuilder
    private var signOutSection: some View {
        Button {
            HapticManager.shared.trigger(.light)
            showingSignOutAlert = true
        } label: {
            HStack(spacing: 12) {
                Spacer()
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .bold))
                Text("Sign Out")
                    .font(.custom("Outfit-Bold", size: 16))
                Spacer()
            }
            .foregroundColor(Color.Brand.warning)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.Brand.warning.opacity(0.1))
            )
        }
        .buttonStyle(SquishyButtonStyle())
        .padding(.top, 16)
    }
}

public struct SettingsRowView: View {
    let icon: String
    var iconColor: Color = Color.Brand.primary
    let title: String
    let showChevron: Bool
    
    public var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                }
                
                Text(title)
                    .font(.custom("Inter-Medium", size: 16))
                    .foregroundColor(Color.Brand.text)
                
                Spacer()
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.gray.opacity(0.5))
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            // Make the whole row tappable consistently
            .contentShape(Rectangle())
        }
        // Use a simple plain style or opacity-changing style internally
        .buttonStyle(SettingsRowButtonStyle())
    }
}

// A subtle button style for rows that just dims slightly on press
struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gray.opacity(0.05) : Color.clear)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview {
    SettingsView()
}
