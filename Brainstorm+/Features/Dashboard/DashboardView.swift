import SwiftUI

struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var ns
    
    var body: some View {
        ZStack {
            Color.Brand.background
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection
                    timeCardSection
                    scheduleSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 120) // tab bar
            }
        }
        .task {
            await viewModel.loadDashboard()
        }
        .refreshable {
            await viewModel.loadDashboard()
        }
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Avatar
            if viewModel.state == .loading {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 56, height: 56)
                    .shimmer()
                
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 20)
                        .shimmer()
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 16)
                        .shimmer()
                }
            } else {
                // Loaded/Error state
                ZStack {
                    Circle()
                        .fill(Color.Brand.accent.opacity(0.2))
                    
                    Text(String(viewModel.profile?.fullName?.prefix(1) ?? "U"))
                        .font(.custom("PlusJakartaSans-Bold", size: 24))
                        .foregroundColor(Color.Brand.primary)
                }
                .frame(width: 56, height: 56)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome back,")
                        .font(.custom("PlusJakartaSans-Regular", size: 14))
                        .foregroundColor(Color.gray)
                    
                    Text(viewModel.profile?.fullName ?? "User")
                        .font(.custom("PlusJakartaSans-Bold", size: 20))
                        .foregroundColor(Color.Brand.text)
                }
            }
            
            Spacer()
            
            // Notification Bell
            Button {
                HapticManager.shared.trigger(.light)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 24))
                        .foregroundColor(Color.Brand.text)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.gray.opacity(0.05))
                        )
                    
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                        .offset(x: -2, y: 2)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var timeCardSection: some View {
        // Quick visual card for today's summary
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Overview")
                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                    .foregroundColor(Color.Brand.text)
                Spacer()
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.custom("PlusJakartaSans-Medium", size: 14))
                    .foregroundColor(Color.Brand.primary)
            }
            
            HStack(spacing: 16) {
                // Stats Box 1
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundColor(Color.Brand.accent)
                    
                    if viewModel.state == .loading {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 28)
                            .shimmer()
                    } else {
                        Text("\(viewModel.todaySchedules.count)")
                            .font(.custom("PlusJakartaSans-Bold", size: 28))
                            .foregroundColor(Color.Brand.text)
                    }
                    
                    Text("Events")
                        .font(.custom("PlusJakartaSans-Medium", size: 14))
                        .foregroundColor(Color.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.Brand.surface)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.02), radius: 10, y: 4)
                
                // Stats Box 2
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundColor(Color.Brand.secondary)
                    
                    if viewModel.state == .loading {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 40, height: 28)
                            .shimmer()
                    } else {
                        let completed = viewModel.todaySchedules.filter({ $0.status == "completed" }).count
                        Text("\(completed)")
                            .font(.custom("PlusJakartaSans-Bold", size: 28))
                            .foregroundColor(Color.Brand.text)
                    }
                    
                    Text("Completed")
                        .font(.custom("PlusJakartaSans-Medium", size: 14))
                        .foregroundColor(Color.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.Brand.surface)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.02), radius: 10, y: 4)
            }
        }
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Upcoming Schedule")
                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                    .foregroundColor(Color.Brand.text)
                
                Spacer()
                
                Button("See All") {
                    // Navigate to full calendar view
                }
                .font(.custom("PlusJakartaSans-Medium", size: 14))
                .foregroundColor(Color.Brand.primary)
            }
            
            switch viewModel.state {
            case .loading:
                // Show 3 skeleton cards
                ForEach(0..<3, id: \.self) { _ in
                    skeletonCard
                }
            case .loaded:
                if viewModel.todaySchedules.isEmpty {
                    emptyStateView
                } else {
                    let sorted = viewModel.todaySchedules.sorted { $0.startTime < $1.startTime }
                    ForEach(sorted) { schedule in
                        ScheduleCardView(schedule: schedule)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            case .error(let msg):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Failed to load schedule")
                        .font(.custom("PlusJakartaSans-Medium", size: 16))
                    Text(msg)
                        .font(.custom("PlusJakartaSans-Regular", size: 12))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.loadDashboard() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.Brand.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(Color.Brand.surface)
                .cornerRadius(24)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.Brand.primary.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 32))
                    .foregroundColor(Color.Brand.primary)
            }
            .padding(.bottom, 8)
            
            Text("No events today")
                .font(.custom("PlusJakartaSans-Bold", size: 18))
                .foregroundColor(Color.Brand.text)
            
            Text("Looks like you have a free day ahead. Take some time to relax or plan ahead.")
                .font(.custom("PlusJakartaSans-Regular", size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.Brand.surface)
        .cornerRadius(24)
    }
    
    private var skeletonCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 16)
                    .shimmer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 30, height: 12)
                    .shimmer()
            }
            .frame(width: 60)
            
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 20)
                    .shimmer()
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 16)
                    .shimmer()
                
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 16)
                        .shimmer()
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 16)
                        .shimmer()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
        }
    }
}

