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
            
            VStack(spacing: 32) {
                // MARK: - Header
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(Color.Brand.primary)
                    
                    Text("BrainStorm+")
                        .font(.custom("PlusJakartaSans-Bold", size: 32, relativeTo: .largeTitle))
                        .foregroundStyle(Color.Brand.text)
                    
                    Text("Sign in to continue")
                        .font(.custom("PlusJakartaSans-Medium", size: 16, relativeTo: .body))
                        .foregroundStyle(Color.Brand.text.opacity(0.6))
                }
                .padding(.top, 80)
                
                // MARK: - Form
                VStack(spacing: 16) {
                    // Email Field
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundStyle(focusedField == .email ? Color.Brand.primary : Color.gray)
                            .frame(width: 24)
                        TextField("Email address", text: $email)
                            .font(.custom("PlusJakartaSans-Regular", size: 16, relativeTo: .body))
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .email)
                            .onChange(of: focusedField) { _, newValue in
                                if newValue == .email { HapticManager.shared.trigger(.soft) }
                            }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(focusedField == .email ? Color.Brand.primary : Color.clear, lineWidth: 2)
                    )
                    
                    // Password Field
                    HStack {
                        Image(systemName: "lock")
                            .foregroundStyle(focusedField == .password ? Color.Brand.primary : Color.gray)
                            .frame(width: 24)
                        SecureField("Password", text: $password)
                            .font(.custom("PlusJakartaSans-Regular", size: 16, relativeTo: .body))
                            .focused($focusedField, equals: .password)
                            .onChange(of: focusedField) { _, newValue in
                                if newValue == .password { HapticManager.shared.trigger(.soft) }
                            }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(focusedField == .password ? Color.Brand.primary : Color.clear, lineWidth: 2)
                    )
                }
                .padding(.horizontal, 24)
                
                // MARK: - Action Button
                Button(action: handleLogin) {
                    HStack(spacing: 12) {
                        if isLoggingIn {
                            ProgressView()
                                .tint(.white)
                            Text("Signing In...")
                                .font(.custom("PlusJakartaSans-SemiBold", size: 16, relativeTo: .body))
                        } else {
                            Text("Sign In")
                                .font(.custom("PlusJakartaSans-SemiBold", size: 16, relativeTo: .body))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.Brand.accent)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .shadow(color: Color.Brand.accent.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 24)
                .disabled(isLoggingIn || email.isEmpty || password.isEmpty)
                .opacity((email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                .offset(x: shakeOffset)
                
                if let errorMessage {
                    Text(errorMessage)
                        .font(.custom("PlusJakartaSans-Medium", size: 14, relativeTo: .footnote))
                        .foregroundStyle(Color.red)
                        .padding(.top, 8)
                }
                
                Spacer()
            }
        }
        .onTapGesture {
            focusedField = nil
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: focusedField)
    }
    
    private func handleLogin() {
        guard !email.isEmpty, !password.isEmpty else {
            triggerErrorShake(message: "Fields cannot be empty")
            return
        }
        
        HapticManager.shared.trigger(.medium)
        focusedField = nil
        errorMessage = nil
        
        withAnimation {
            isLoggingIn = true
        }
        
        // Mock network delay for UX showcase until actual Supabase connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            HapticManager.shared.trigger(.success)
            sessionManager.login()
            isLoggingIn = false
        }
    }
    
    private func triggerErrorShake(message: String) {
        HapticManager.shared.trigger(.error)
        errorMessage = message
        
        withAnimation(.default) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.default) { shakeOffset = -10 }
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
