import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authState: AuthStateManager
    @EnvironmentObject var realtimeSync: RealtimeSyncManager
    
    @State private var recentEvents: [String] = []
    
    var body: some View {
        TabView {
            // Home Tab
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            Text("Realtime Status")
                                .font(Font.ZY.h2)
                            Spacer()
                            Circle()
                                .fill(realtimeSync.isConnected ? Color.ZY.success : Color.ZY.warning)
                                .frame(width: 12, height: 12)
                                .shadow(color: realtimeSync.isConnected ? Color.ZY.success.opacity(0.4) : Color.ZY.warning.opacity(0.4), radius: 4)
                        }
                        
                        VStack(spacing: 12) {
                            if recentEvents.isEmpty {
                                Text("No recent syncing activity.")
                                    .font(Font.ZY.caption)
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                ForEach(recentEvents.reversed(), id: \.self) { event in
                                    HStack {
                                        Text(event)
                                            .font(Font.ZY.body)
                                        Spacer()
                                    }
                                    .padding()
                                    .background(Color.ZY.dynamicPaper)
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color.ZY.surfaceBg.ignoresSafeArea())
                .navigationTitle("Dashboard")
                .toolbar {
                    Button("Sign Out") {
                        Task { try? await supabase.auth.signOut() }
                    }
                }
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            
            // Settings Tab
            NavigationStack {
                Text("Settings coming soon")
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .task {
            // Example of binding to Realtime Sync instantly upon loading
            await realtimeSync.subscribeToTableChanges(tableName: "attendance") { change in
                let changeStr = String(describing: change)
                recentEvents.append("Attendance updated")
            }
        }
    }
}

#Preview {
    DashboardView()
}
