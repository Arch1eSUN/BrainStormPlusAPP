import SwiftUI
import Supabase

public struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var showingSignOutAlert = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.Brand.background
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    generalSection
                    supportSection
                    signOutSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 120) // tab bar spacing
            }
        }
        .task {
            await viewModel.loadProfile()
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                HapticManager.shared.trigger(.medium)
                Task {
                    await viewModel.signOut()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
    
    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 16) {
            if viewModel.isLoading {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .shimmer()
                
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 140, height: 24)
                        .shimmer()
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 100, height: 16)
                        .shimmer()
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.Brand.accent.opacity(0.2))
                    
                    Text(String(viewModel.profile?.fullName?.prefix(1) ?? "U"))
                        .font(.custom("PlusJakartaSans-Bold", size: 36))
                        .foregroundColor(Color.Brand.primary)
                }
                .frame(width: 80, height: 80)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.profile?.fullName ?? "User")
                        .font(.custom("PlusJakartaSans-Bold", size: 24))
                        .foregroundColor(Color.Brand.text)
                    
                    Text(viewModel.profile?.role?.capitalized ?? "Team Member")
                        .font(.custom("PlusJakartaSans-Medium", size: 14))
                        .foregroundColor(Color.Brand.primary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    @ViewBuilder
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                .foregroundColor(Color.gray)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                SettingsRowView(icon: "bell.badge", title: "Notifications", showChevron: true)
                Divider().background(Color.white.opacity(0.1)).padding(.leading, 56)
                SettingsRowView(icon: "lock.shield", title: "Privacy & Security", showChevron: true)
                Divider().background(Color.white.opacity(0.1)).padding(.leading, 56)
                SettingsRowView(icon: "paintpalette", title: "Appearance", showChevron: true)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.Brand.surface)
            )
        }
    }
    
    @ViewBuilder
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Support")
                .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                .foregroundColor(Color.gray)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                SettingsRowView(icon: "questionmark.circle", title: "Help Center", showChevron: true)
                Divider().background(Color.white.opacity(0.1)).padding(.leading, 56)
                SettingsRowView(icon: "doc.text", title: "Terms of Service", showChevron: true)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.Brand.surface)
            )
        }
    }
    
    @ViewBuilder
    private var signOutSection: some View {
        Button {
            HapticManager.shared.trigger(.light)
            showingSignOutAlert = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
                    .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                Spacer()
            }
            .foregroundColor(.red)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.red.opacity(0.1))
            )
        }
        .padding(.top, 10)
    }
}

public struct SettingsRowView: View {
    let icon: String
    let title: String
    let showChevron: Bool
    
    public var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.Brand.primary.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(Color.Brand.primary)
                }
                
                Text(title)
                    .font(.custom("PlusJakartaSans-Medium", size: 16))
                    .foregroundColor(Color.Brand.text)
                
                Spacer()
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.gray)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
}
