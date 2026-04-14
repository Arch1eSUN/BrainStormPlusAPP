import SwiftUI

public struct AttendanceView: View {
    @State private var viewModel = AttendanceViewModel()
    
    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 24) {
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.custom("PlusJakartaSans-Medium", size: 14))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(12)
            }
            
            ZStack {
                // Background Glow
                Circle()
                    .fill(buttonColor.opacity(0.2))
                    .frame(width: 220, height: 220)
                    .blur(radius: 20)
                
                // Multi-layered Button
                Button {
                    HapticManager.shared.trigger(.medium)
                    Task { await viewModel.toggleClockStatus() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(buttonColor)
                            .shadow(color: buttonColor.opacity(0.4), radius: 20, x: 0, y: 10)
                        
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            .padding(4)
                        
                        VStack(spacing: 8) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(1.5)
                            } else {
                                Image(systemName: iconName)
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text(buttonText)
                                    .font(.custom("PlusJakartaSans-Bold", size: 24))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(width: 180, height: 180)
                }
                .disabled(viewModel.isLoading || isCompleted)
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.top, 16)
            
            // Status Info
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Text("Clock In")
                        .font(.custom("PlusJakartaSans-Medium", size: 14))
                        .foregroundColor(Color.gray)
                    
                    if let inTime = viewModel.currentAttendance?.clockIn {
                        Text(timeFormatter.string(from: inTime))
                            .font(.custom("PlusJakartaSans-Bold", size: 18))
                            .foregroundColor(Color.Brand.text)
                    } else {
                        Text("--:--")
                            .font(.custom("PlusJakartaSans-Bold", size: 18))
                            .foregroundColor(Color.gray.opacity(0.5))
                    }
                }
                
                Divider()
                    .frame(height: 40)
                
                VStack(spacing: 4) {
                    Text("Clock Out")
                        .font(.custom("PlusJakartaSans-Medium", size: 14))
                        .foregroundColor(Color.gray)
                    
                    if let outTime = viewModel.currentAttendance?.clockOut {
                        Text(timeFormatter.string(from: outTime))
                            .font(.custom("PlusJakartaSans-Bold", size: 18))
                            .foregroundColor(Color.Brand.text)
                    } else {
                        Text("--:--")
                            .font(.custom("PlusJakartaSans-Bold", size: 18))
                            .foregroundColor(Color.gray.opacity(0.5))
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            )
        }
        .task {
            await viewModel.fetchTodayAttendance()
        }
    }
    
    // UI Helpers
    private var isClockedIn: Bool {
        viewModel.currentAttendance?.clockIn != nil
    }
    
    private var isClockedOut: Bool {
        viewModel.currentAttendance?.clockOut != nil
    }
    
    private var isCompleted: Bool {
        isClockedIn && isClockedOut
    }
    
    private var buttonText: String {
        if isCompleted { return "Done" }
        if isClockedIn { return "Clock \nOut" }
        return "Clock \nIn"
    }
    
    private var iconName: String {
        if isCompleted { return "checkmark" }
        if isClockedIn { return "arrow.uturn.left" }
        return "hand.tap.fill"
    }
    
    private var buttonColor: Color {
        if isCompleted { return Color.gray }
        if isClockedIn { return Color.orange }
        return Color.Brand.primary
    }
}

// Custom Button Style for squishy tactile feel
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        AttendanceView()
    }
}
