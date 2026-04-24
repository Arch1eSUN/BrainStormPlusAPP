import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch B.1 — Reporting list with CRUD entry points.
//
// One-view parity with Web's two pages (/dashboard/daily and
// /dashboard/weekly). iOS keeps the single tab in the app module
// registry and splits the content via a local segmented picker.
// ══════════════════════════════════════════════════════════════════

public struct ReportingListView: View {
    @StateObject private var viewModel: ReportingViewModel

    @State private var dailyEditTarget: DailyLogEditTarget?
    @State private var weeklyEditTarget: WeeklyEditTarget?

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(viewModel: ReportingViewModel, isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.isEmbedded = isEmbedded
    }

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("视图", selection: $viewModel.selectedTab) {
                    ForEach(ReportingViewModel.Tab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: viewModel.selectedTab) { _, _ in Haptic.selection() }

                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    switch viewModel.selectedTab {
                    case .daily:
                        dailySection
                    case .weekly:
                        weeklySection
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("报告")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptic.light()
                    switch viewModel.selectedTab {
                    case .daily:  dailyEditTarget = .new
                    case .weekly: weeklyEditTarget = .new
                    }
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .accessibilityLabel("新建报告")
            }
        }
        .refreshable {
            await viewModel.fetchReports()
        }
        .task {
            await viewModel.fetchReports()
        }
        .sheet(item: $dailyEditTarget) { target in
            DailyLogEditView(
                viewModel: viewModel,
                existingLog: target.log
            )
        }
        .sheet(item: $weeklyEditTarget) { target in
            WeeklyReportEditView(
                viewModel: viewModel,
                existingReport: target.report
            )
        }
        .zyErrorBanner($viewModel.errorMessage)
    }

    // ── Daily ────────────────────────────────────────────────────
    @ViewBuilder
    private var dailySection: some View {
        if viewModel.dailyLogs.isEmpty {
            BsEmptyState(
                title: "暂无日志",
                systemImage: "doc.text",
                description: "开始记录你的第一篇工作日志"
            )
            .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.dailyLogs) { log in
                    DailyLogCardView(log: log)
                        .padding(.horizontal)
                        .onTapGesture {
                            dailyEditTarget = .edit(log)
                        }
                        .contextMenu {
                            Button("编辑") { dailyEditTarget = .edit(log) }
                            Button("删除", role: .destructive) {
                                Task { await viewModel.deleteLog(log) }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteLog(log) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                dailyEditTarget = .edit(log)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
    }

    // ── Weekly ───────────────────────────────────────────────────
    @ViewBuilder
    private var weeklySection: some View {
        if viewModel.weeklyReports.isEmpty {
            BsEmptyState(
                title: "暂无周报",
                systemImage: "calendar",
                description: "保存你的第一篇周报"
            )
            .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.weeklyReports) { r in
                    WeeklyReportCardView(report: r)
                        .padding(.horizontal)
                        .onTapGesture {
                            weeklyEditTarget = .edit(r)
                        }
                        .contextMenu {
                            Button("编辑") { weeklyEditTarget = .edit(r) }
                            Button("删除", role: .destructive) {
                                Task { await viewModel.deleteWeeklyReport(r) }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteWeeklyReport(r) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                weeklyEditTarget = .edit(r)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            }
        }
    }
}

// ══════════════════════════════════════════════════════════════════
// Sheet target wrappers (Identifiable) — required by `.sheet(item:)`.
// ══════════════════════════════════════════════════════════════════

private enum DailyLogEditTarget: Identifiable {
    case new
    case edit(DailyLog)

    var id: String {
        switch self {
        case .new:           return "new"
        case .edit(let log): return log.id.uuidString
        }
    }

    var log: DailyLog? {
        switch self {
        case .new:           return nil
        case .edit(let log): return log
        }
    }
}

private enum WeeklyEditTarget: Identifiable {
    case new
    case edit(WeeklyReport)

    var id: String {
        switch self {
        case .new:              return "new"
        case .edit(let report): return report.id.uuidString
        }
    }

    var report: WeeklyReport? {
        switch self {
        case .new:              return nil
        case .edit(let report): return report
        }
    }
}
