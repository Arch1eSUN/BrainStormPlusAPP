import SwiftUI
import UIKit

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
    // Long-press 增强 (longpress-system §菜单结构原则: hoisted destructive state):
    // 删除走 confirmationDialog 二次确认而不是 contextMenu 直接 mutate。
    // hoisted 到 view 根,daily / weekly 共用同一对 state 互不干扰。
    @State private var pendingDeleteDaily: DailyLog?
    @State private var pendingDeleteWeekly: WeeklyReport?

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
                // Haptic removed: 用户反馈 picker 切换过密震动

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
                    // Haptic removed: 用户反馈 toolbar 按钮过密震动
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
        .confirmationDialog(
            "确认删除",
            isPresented: Binding(
                get: { pendingDeleteDaily != nil },
                set: { if !$0 { pendingDeleteDaily = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteDaily
        ) { target in
            Button("删除", role: .destructive) {
                Haptic.error()
                Task { await viewModel.deleteLog(target) }
                pendingDeleteDaily = nil
            }
            Button("取消", role: .cancel) { pendingDeleteDaily = nil }
        } message: { _ in
            Text("将删除该日报,该操作无法撤销。")
        }
        .confirmationDialog(
            "确认删除",
            isPresented: Binding(
                get: { pendingDeleteWeekly != nil },
                set: { if !$0 { pendingDeleteWeekly = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteWeekly
        ) { target in
            Button("删除", role: .destructive) {
                Haptic.error()
                Task { await viewModel.deleteWeeklyReport(target) }
                pendingDeleteWeekly = nil
            }
            Button("取消", role: .cancel) { pendingDeleteWeekly = nil }
        } message: { _ in
            Text("将删除该周报,该操作无法撤销。")
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
            // v1.3.1 perf: VStack → LazyVStack —— daily logs 可能累积到 30-60 条，
            // 非 lazy 版本开屏会一次性构建所有 card body，在 ProMotion 下明显掉帧
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.dailyLogs) { log in
                    DailyLogCardView(log: log)
                        .padding(.horizontal)
                        .onTapGesture {
                            dailyEditTarget = .edit(log)
                        }
                        .contextMenu {
                            // Long-press 增强 (longpress-system §5 日报项):
                            // 编辑 / 复制 / 删除三段式 + Label icon 化。删除走
                            // hoisted confirmationDialog,不再 inline mutate。
                            Button {
                                Haptic.light()
                                dailyEditTarget = .edit(log)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }

                            Button {
                                let dateStr = log.date.formatted(.dateTime.year().month().day())
                                let summary = "\(dateStr)\n\(log.content)"
                                UIPasteboard.general.string = summary
                                Haptic.light()
                            } label: {
                                Label("复制内容", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                Haptic.warning()
                                pendingDeleteDaily = log
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteDaily = log
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
            // v1.3.1 perf: 同 dailySection，改 LazyVStack
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.weeklyReports) { r in
                    WeeklyReportCardView(report: r)
                        .padding(.horizontal)
                        .onTapGesture {
                            weeklyEditTarget = .edit(r)
                        }
                        .contextMenu {
                            // Long-press 增强 (longpress-system §5 周报项)
                            Button {
                                Haptic.light()
                                weeklyEditTarget = .edit(r)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }

                            Button {
                                UIPasteboard.general.string = weeklyClipboardSummary(r)
                                Haptic.light()
                            } label: {
                                Label("复制内容", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                Haptic.warning()
                                pendingDeleteWeekly = r
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteWeekly = r
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

// MARK: - Long-press clipboard helpers

private func weeklyClipboardSummary(_ r: WeeklyReport) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    let start = f.string(from: r.weekStart)
    let end = r.weekEnd.map { f.string(from: $0) } ?? ""
    let header = end.isEmpty ? "周报 \(start)" : "周报 \(start) ~ \(end)"

    var lines: [String] = [header, ""]
    if let s = r.summary, !s.isEmpty {
        lines.append("摘要:")
        lines.append(s)
        lines.append("")
    }
    if let a = r.accomplishments, !a.isEmpty {
        lines.append("成就:")
        lines.append(a)
        lines.append("")
    }
    if let p = r.plans, !p.isEmpty {
        lines.append("计划:")
        lines.append(p)
        lines.append("")
    }
    if let b = r.blockers, !b.isEmpty {
        lines.append("阻碍:")
        lines.append(b)
    }
    return lines.joined(separator: "\n")
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
