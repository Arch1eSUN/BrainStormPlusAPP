import SwiftUI

public struct ScheduleView: View {
    @State private var viewModel = ScheduleViewModel()
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.Brand.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Schedule")
                        .font(.custom("PlusJakartaSans-Bold", size: 28))
                        .foregroundColor(Color.Brand.text)
                    Spacer()
                    
                    // Date Picker
                    DatePicker("", selection: $viewModel.selectedDate, displayedComponents: .date)
                        .labelsHidden()
                        .tint(Color.Brand.primary)
                        .onChange(of: viewModel.selectedDate) { _ in
                            HapticManager.shared.trigger(.light)
                            Task { await viewModel.loadSchedules() }
                        }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 16)
                
                // List
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Attendance Section at the top
                        AttendanceView()
                            .padding(.bottom, 16)
                        
                        // Schedules section
                        if viewModel.isLoading {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 100)
                                    .shimmer()
                            }
                        } else if let error = viewModel.errorMessage {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.custom("PlusJakartaSans-Medium", size: 14))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                Button("Retry") {
                                    Task { await viewModel.loadSchedules() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.Brand.primary)
                            }
                            .padding(.top, 40)
                        } else if viewModel.schedules.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundColor(Color.gray.opacity(0.5))
                                Text("No schedules for this date")
                                    .font(.custom("PlusJakartaSans-Medium", size: 16))
                                    .foregroundColor(Color.Brand.text)
                            }
                            .padding(.top, 60)
                        } else {
                            ForEach(viewModel.schedules) { schedule in
                                ScheduleCardView(schedule: schedule)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
                .refreshable {
                    await viewModel.loadSchedules()
                }
            }
        }
        .task {
            await viewModel.loadSchedules()
        }
    }
}
