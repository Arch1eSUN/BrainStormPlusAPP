import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch B.1 — Weekly report edit sheet.
// Batch C.4a — AI 生成摘要 button + project multi-select wired.
//
// 1:1 surface port of `src/app/dashboard/weekly/page.tsx`. Sections
// match the Web form order: summary, highlights, accomplishments,
// challenges, plans, blockers.
//
// Still deferred:
//   • 拉取本周数据 (`buildWeeklyContext`) — not part of C.4a.
// ══════════════════════════════════════════════════════════════════

public struct WeeklyReportEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var viewModel: ReportingViewModel
    @StateObject private var pickerVM: ReportingPickerViewModel

    private let existingReport: WeeklyReport?

    @State private var weekStart: Date
    @State private var summary: String
    @State private var highlights: String
    @State private var accomplishments: String
    @State private var challenges: String
    @State private var plans: String
    @State private var blockers: String
    @State private var projectIds: [UUID]
    @State private var showDeleteConfirm = false

    public init(viewModel: ReportingViewModel, existingReport: WeeklyReport? = nil) {
        self.viewModel = viewModel
        self.existingReport = existingReport
        _pickerVM = StateObject(wrappedValue: ReportingPickerViewModel(client: supabase))
        _weekStart = State(initialValue: existingReport?.weekStart ?? Self.currentWeekMonday())
        _summary = State(initialValue: existingReport?.summary ?? "")
        _highlights = State(initialValue: existingReport?.highlights ?? "")
        _accomplishments = State(initialValue: existingReport?.accomplishments ?? "")
        _challenges = State(initialValue: existingReport?.challenges ?? "")
        _plans = State(initialValue: existingReport?.plans ?? "")
        _blockers = State(initialValue: existingReport?.blockers ?? "")
        _projectIds = State(initialValue: existingReport?.projectIds ?? [])
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("本周") {
                    if existingReport == nil {
                        DatePicker("周一日期", selection: $weekStart, displayedComponents: .date)
                    } else {
                        HStack {
                            Text("周一日期")
                            Spacer()
                            Text(weekStart, style: .date)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                    }
                    HStack {
                        Text("本周范围")
                        Spacer()
                        Text(formattedWeekRange(from: weekStart))
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }

                Section {
                    Button {
                        Task { await generateAISummary() }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isGeneratingAISummary {
                                ProgressView()
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(viewModel.isGeneratingAISummary ? "AI 正在总结..." : "AI 生成摘要")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isGeneratingAISummary || viewModel.isSaving)
                } footer: {
                    Text("基于本周任务和日报自动生成总结，可覆盖后再编辑。")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }

                longTextSection(title: "本周总结", text: $summary, placeholder: "简要概括本周工作...")
                longTextSection(title: "亮点", text: $highlights, placeholder: "本周亮点和突出贡献...")
                longTextSection(title: "本周成果", text: $accomplishments, placeholder: "完成了哪些任务...")
                longTextSection(title: "挑战与风险", text: $challenges, placeholder: "遇到的困难和潜在风险...")
                longTextSection(title: "下周计划", text: $plans, placeholder: "下周计划做什么...")
                longTextSection(title: "遇到的问题", text: $blockers, placeholder: "有什么阻塞或困难...")

                Section("关联项目") {
                    if pickerVM.isLoadingProjects && pickerVM.projects.isEmpty {
                        HStack {
                            ProgressView()
                            Text("加载中...").foregroundStyle(BsColor.inkMuted)
                        }
                    } else if pickerVM.projects.isEmpty {
                        Text("暂无可选项目")
                            .foregroundStyle(BsColor.inkMuted)
                    } else {
                        ForEach(pickerVM.projects) { project in
                            let isOn = projectIds.contains(project.id)
                            Button {
                                if isOn {
                                    projectIds.removeAll { $0 == project.id }
                                } else {
                                    projectIds.append(project.id)
                                }
                            } label: {
                                HStack {
                                    Text(project.name)
                                        .foregroundStyle(BsColor.ink)
                                    Spacer()
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isOn ? BsColor.brandAzure : BsColor.inkMuted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if existingReport != nil {
                    Section {
                        Button("删除周报", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(existingReport == nil ? "新建周报" : "编辑周报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingReport == nil ? "保存" : "更新") {
                        Task { await save() }
                    }
                    .disabled(viewModel.isSaving || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if viewModel.isSaving {
                    ProgressView().controlSize(.large)
                }
            }
            .confirmationDialog(
                "确认删除这篇周报？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    Task {
                        if let r = existingReport {
                            await viewModel.deleteWeeklyReport(r)
                            if viewModel.errorMessage == nil { dismiss() }
                        }
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("删除后无法恢复。")
            }
            .task {
                if pickerVM.projects.isEmpty {
                    await pickerVM.loadProjects()
                }
            }
            .zyErrorBanner($viewModel.errorMessage)
        }
    }

    /// Calls the AI endpoint, then fills `summary` (and
    /// `accomplishments` when the response structure permits). Mirrors
    /// Web's `handleAISummary` in `src/app/dashboard/weekly/page.tsx`.
    private func generateAISummary() async {
        guard let result = await viewModel.generateAIWeeklySummary(weekStart: weekStart) else {
            return
        }
        // Web overwrites summary unconditionally on success; we match.
        summary = result.summary
        // Only fill accomplishments when the user hasn't typed any.
        // This keeps us safe from clobbering hand-written content if
        // the user hits the button twice.
        if let fill = result.accomplishments,
           accomplishments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            accomplishments = fill
        }
    }

    @ViewBuilder
    private func longTextSection(title: String, text: Binding<String>, placeholder: String) -> some View {
        Section(title) {
            TextEditor(text: text)
                .frame(minHeight: 90)
            if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }
        }
    }

    private func save() async {
        let saved = await viewModel.saveWeeklyReport(
            weekStart: weekStart,
            summary: summary,
            accomplishments: accomplishments.isEmpty ? nil : accomplishments,
            plans: plans.isEmpty ? nil : plans,
            blockers: blockers.isEmpty ? nil : blockers,
            highlights: highlights.isEmpty ? nil : highlights,
            challenges: challenges.isEmpty ? nil : challenges,
            projectIds: projectIds
        )
        if saved != nil {
            dismiss()
        }
    }

    // ── Helpers ───────────────────────────────────────────────────
    private static func currentWeekMonday(reference: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday, to match Web `getWeekStart`
        let weekday = cal.component(.weekday, from: reference) // Sun=1 … Sat=7
        // Compute offset so Monday yields 0, Sunday yields -6.
        let offset = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: reference)) ?? reference
    }

    private func formattedWeekRange(from start: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return "\(f.string(from: start)) — \(f.string(from: end))"
    }
}
