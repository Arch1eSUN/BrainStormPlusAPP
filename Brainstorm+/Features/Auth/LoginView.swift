import SwiftUI
import Supabase

struct LoginView: View {
    @Environment(SessionManager.self) private var sessionManager
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var shakeOffset: CGFloat = 0
    @State private var errorMessage: String?
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }
    
    var body: some View {
        ZStack {
            Color.Brand.background.ignoresSafeArea()
            
            // Decorative background elements
            Circle()
                .fill(Color.Brand.primary.opacity(0.05))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: -100, y: -200)
            
            Circle()
                .fill(Color.Brand.accent.opacity(0.05))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: 150, y: 100)
            
            VStack(spacing: 32) {
                Spacer().frame(height: 60)
                
                // MARK: - Header
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.Brand.primary.opacity(0.05))
                            .frame(width: 88, height: 88)
                        
                        Image("BrandLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    VStack(spacing: 8) {
                        Text("BrainStorm+")
                            .font(.custom("Outfit-Bold", size: 36, relativeTo: .largeTitle))
                            .foregroundStyle(Color.Brand.text)
                        
                        Text("Welcome back, visionary.")
                            .font(.custom("Inter-Medium", size: 16, relativeTo: .body))
                            .foregroundStyle(Color.Brand.textSecondary)
                    }
                }
                
                Spacer().frame(height: 16)
                
                // MARK: - Form
                VStack(spacing: 16) {
                    // Email Field
                    HStack(spacing: 16) {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(focusedField == .email ? Color.Brand.primary : Color.gray.opacity(0.5))
                            .font(.system(size: 18))
                            .frame(width: 24)
                        
                        TextField("Work Email", text: $email)
                            .font(.custom("Inter-Regular", size: 16, relativeTo: .body))
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .onChange(of: focusedField) { _, newValue in
                                if newValue == .email { HapticManager.shared.trigger(.soft) }
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(focusedField == .email ? Color.Brand.primary : Color.clear, lineWidth: 2)
                    )
                    
                    // Password Field
                    HStack(spacing: 16) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(focusedField == .password ? Color.Brand.primary : Color.gray.opacity(0.5))
                            .font(.system(size: 18))
                            .frame(width: 24)
                        
                        SecureField("Password", text: $password)
                            .font(.custom("Inter-Regular", size: 16, relativeTo: .body))
                            .focused($focusedField, equals: .password)
                            .onChange(of: focusedField) { _, newValue in
                                if newValue == .password { HapticManager.shared.trigger(.soft) }
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(focusedField == .password ? Color.Brand.primary : Color.clear, lineWidth: 2)
                    )
                }
                .padding(.horizontal, 24)
                
                // MARK: - Action Button
                VStack(spacing: 16) {
                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(errorMessage)
                                .font(.custom("Inter-Medium", size: 14))
                        }
                        .foregroundStyle(Color.Brand.warning)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.Brand.warning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    
                    Button(action: handleLogin) {
                        HStack(spacing: 12) {
                            if isLoggingIn {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isLoggingIn ? "Authenticating..." : "Sign In")
                                .font(.custom("Outfit-Bold", size: 18, relativeTo: .body))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.Brand.primary)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.Brand.primary.opacity(0.3), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(SquishyButtonStyle())
                    .padding(.horizontal, 24)
                    .disabled(isLoggingIn || email.isEmpty || password.isEmpty)
                    .opacity((email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                    .offset(x: shakeOffset)
                }
                
                Spacer()
            }
        }
        .onTapGesture {
            focusedField = nil
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: focusedField)
    }
    
    private func handleLogin() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            triggerErrorShake(message: "Fields cannot be empty")
            return
        }
        
        HapticManager.shared.trigger(.medium)
        focusedField = nil
        errorMessage = nil
        
        withAnimation(.spring()) {
            isLoggingIn = true
        }
        
        Task {
            do {
                try await sessionManager.login(email: trimmedEmail, password: password)
                HapticManager.shared.trigger(.success)
            } catch {
                await MainActor.run {
                    withAnimation { isLoggingIn = false }
                    triggerErrorShake(message: error.localizedDescription)
                }
            }
        }
    }
    
    private func triggerErrorShake(message: String) {
        HapticManager.shared.trigger(.error)
        errorMessage = message
        
        withAnimation(.default) { shakeOffset = 15 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.default) { shakeOffset = -15 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.default) { shakeOffset = 0 }
        }
    }
}

#Preview {
    LoginView()
        .environment(SessionManager())
}
