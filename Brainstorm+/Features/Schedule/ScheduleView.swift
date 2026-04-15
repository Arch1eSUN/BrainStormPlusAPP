import SwiftUI

public struct ScheduleView: View {
    @State private var viewModel = ScheduleViewModel()
    @Namespace private var topAnimation
    
    // For smooth horizontal date swiping
    @State private var dates: [Date] = []
    
    public init() {}
    
    private func setupDates() {
        let calendar = Calendar.current
        let today = Date()
        // Generate -3 to +7 days around today
        for i in -3...7 {
            if let date = calendar.date(byAdding: .day, value: i, to: today) {
                dates.append(date)
            }
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.Brand.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header & Horizontal Date Picker
                    headerSection
                        .zIndex(10)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            
                            // Map existing Geofence component. 
                            // Since AttendanceView is large, we wrap it cleanly.
                            AttendanceView()
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
                            
                            // Events
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Events")
                                    .font(.custom("Outfit-SemiBold", size: 18))
                                    .foregroundColor(Color.Brand.text)
                                
                                if viewModel.isLoading {
                                    ForEach(0..<3, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.Brand.paper)
                                            .frame(height: 100)
                                            .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
                                            .shimmer()
                                    }
                                } else if let error = viewModel.errorMessage {
                                    errorState(error)
                                } else if viewModel.schedules.isEmpty {
                                    emptyState
                                } else {
                                    ForEach(viewModel.schedules) { schedule in
                                        ScheduleCardView(schedule: schedule)
                                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                                    }
                                }
                            }
                        }
                        .padding(.top, 24)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 120) // safe space for tabbar
                    }
                    .refreshable {
                        HapticManager.shared.trigger(.soft)
                        await viewModel.loadSchedules()
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            if dates.isEmpty { setupDates() }
        }
        .task {
            await viewModel.loadSchedules()
        }
    }
    
    // MARK: - Components
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Schedule")
                    .font(.custom("Outfit-Bold", size: 32))
                    .foregroundColor(Color.Brand.text)
                 Spacer()
                
                // Jump to Today
                Button(action: {
                    HapticManager.shared.trigger(.light)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.selectedDate = Date()
                        Task { await viewModel.loadSchedules() }
                    }
                }) {
                    Text("Today")
                        .font(.custom("Inter-Medium", size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.Brand.primary)
                        .clipShape(Capsule())
                        .shadow(color: Color.Brand.primary.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(SquishyButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            // Horizontal Date strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(dates, id: \.self) { date in
                        datePill(for: date)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .background(Color.Brand.background.opacity(0.95))
        .background(.ultraThinMaterial)
    }
    
    private func datePill(for date: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(date, inSameDayAs: viewModel.selectedDate)
        
        let dfDay = DateFormatter()
        dfDay.dateFormat = "EEE" // Mon, Tue...
        let dayStr = dfDay.string(from: date).uppercased()
        
        let dfNum = DateFormatter()
        dfNum.dateFormat = "d"   // 1, 2, 3...
        let numStr = dfNum.string(from: date)
        
        return Button(action: {
            HapticManager.shared.trigger(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.selectedDate = date
            }
            Task { await viewModel.loadSchedules() }
        }) {
            VStack(spacing: 4) {
                Text(dayStr)
                    .font(.custom("Inter-Medium", size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : Color.gray)
                
                Text(numStr)
                    .font(.custom("Outfit-Bold", size: 18))
                    .foregroundColor(isSelected ? .white : Color.Brand.text)
            }
            .frame(width: 56, height: 72)
            .background {
                if isSelected {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.Brand.primary)
                            .shadow(color: Color.Brand.primary.opacity(0.3), radius: 6, y: 3)
                        
                        // Subtle top glow highlight for depth
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    }
                    .matchedGeometryEffect(id: "selectedDateBg", in: topAnimation)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.Brand.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.04), lineWidth: 1)
                        )
                }
            }
        }
        .buttonStyle(SquishyButtonStyle())
    }
    
    @ViewBuilder
    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(Color.Brand.warning)
            Text("Failed to load")
                .font(.custom("Outfit-SemiBold", size: 16))
                .foregroundColor(Color.Brand.text)
            Text(msg)
                .font(.custom("Inter-Regular", size: 14))
                .foregroundColor(Color.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.Brand.accent.opacity(0.08))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(Color.Brand.accent)
            }
            
            Text("No events scheduled")
                .font(.custom("Outfit-Medium", size: 16))
                .foregroundColor(Color.Brand.text)
            
            Button("Add Event") { 
                HapticManager.shared.trigger(.medium) 
            }
            .font(.custom("Inter-Medium", size: 14))
            .foregroundColor(Color.Brand.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.Brand.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
    }
}
