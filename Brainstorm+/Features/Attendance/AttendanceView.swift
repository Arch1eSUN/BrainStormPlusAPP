import SwiftUI
import Combine

public struct AttendanceView: View {
    @StateObject private var viewModel = AttendanceViewModel()
    @State private var isPulsing = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Check-in")
                        .font(.custom("Outfit-Bold", size: 20))
                        .foregroundColor(Color.Brand.text)
                    
                    Text(Date().formatted(date: .complete, time: .omitted))
                        .font(.custom("Inter-Medium", size: 14))
                        .foregroundColor(Color.Brand.textSecondary)
                }
                
                Spacer()
                
                // Status Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.canClockIn ? Color.Brand.primary : Color.Brand.warning)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isPulsing ? 1.2 : 0.8)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: isPulsing)
                    
                    Text(viewModel.canClockIn ? "In Zone" : "Out of Zone")
                        .font(.custom("Inter-SemiBold", size: 12))
                        .foregroundColor(viewModel.canClockIn ? Color.Brand.primary : Color.Brand.warning)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((viewModel.canClockIn ? Color.Brand.primary : Color.Brand.warning).opacity(0.1))
                .clipShape(Capsule())
            }
            
            // Map or Zone indicator placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.Brand.background)
                    .frame(height: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
                
                // Pulsing rings indicating current location
                ZStack {
                    Circle()
                        .stroke(Color.Brand.primary.opacity(0.2), lineWidth: 1)
                        .frame(width: 80, height: 80)
                        .scaleEffect(isPulsing ? 1.5 : 1.0)
                        .opacity(isPulsing ? 0 : 1)
                    
                    Circle()
                        .fill(Color.Brand.primary.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .scaleEffect(isPulsing ? 1.2 : 1.0)
                        .opacity(isPulsing ? 0.3 : 1)
                    
                    Image(systemName: "location.fill")
                        .foregroundColor(Color.Brand.primary)
                        .font(.system(size: 20))
                }
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isPulsing)
                
                VStack {
                    Spacer()
                    HStack {
                        Text(viewModel.currentLocationName ?? "Locating...")
                            .font(.custom("Inter-Medium", size: 12))
                            .foregroundColor(Color.Brand.textSecondary)
                        Spacer()
                    }
                    .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            
            // Big Clock In Button
            Button(action: {
                HapticManager.shared.trigger(.success)
                Task { await viewModel.clockIn() }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.canClockIn ? "hand.tap.fill" : "lock.fill")
                        .font(.system(size: 18))
                    Text(viewModel.canClockIn ? "Clock In" : "Not available")
                        .font(.custom("Outfit-Bold", size: 16))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(viewModel.canClockIn ? Color.Brand.primary : Color.gray.opacity(0.3))
                .foregroundColor(viewModel.canClockIn ? .white : .gray)
                .clipShape(Capsule())
                .shadow(color: viewModel.canClockIn ? Color.Brand.primary.opacity(0.3) : .clear, radius: 8, y: 4)
            }
            .disabled(!viewModel.canClockIn || viewModel.isLoading)
            .buttonStyle(SquishyButtonStyle())
        }
        .padding(24)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        .onAppear {
            isPulsing = true
        }
    }
}
