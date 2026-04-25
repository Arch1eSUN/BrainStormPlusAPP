import SwiftUI
import Charts
import Supabase

// ══════════════════════════════════════════════════
// BrainStorm+ iOS — Finance AI Workspace
//
// 1:1 port of Web `src/app/dashboard/finance/page.tsx`.
// Web 页面由三大分区组成：
//   1. Chain selector (文档整理 / 报表整理 / 数据处理)
//   2. 输入区 + AI 处理按钮 (文本 + 文件上传)
//   3. 结构化结果展示 + 历史列表
//
// 输入 + 提交动作已通过 POST /api/mobile/finance/ai-process 接入（Phase
// 5.3）；三链路径 document_organize / report_summarize / data_process 共用
// 同一张 ai_work_records 表。
// 导出 (CSV/PDF) Web 也暂无此能力，iOS 跟随 SKIP。
// ══════════════════════════════════════════════════

public struct FinanceView: View {
    @StateObject private var viewModel: FinanceViewModel
    @Environment(SessionManager.self) private var sessionManager
    // Bug-fix(财务历史:点了停在当前页,返回后才显示):
    // 上一轮把 sheet 改成 toolbar `NavigationLink(value: HistoryRoute.all)` +
    // `.navigationDestination(for: HistoryRoute.self)`,但在 isEmbedded=true
    // (从 BsCommandPalette / DashboardWidget 进入,palette 自己持有 NavStack)
    // 时,toolbar 的 NavigationLink(value:) 与外层 palette 的 view-based push
    // 在 iOS 26 上不稳定 —— 用户点了"历史"按钮,push 触发但 destination
    // body 没渲染 (panel stale state),只能在 pop 回去时 SwiftUI 才补绘出来。
    //
    // 改回 sheet pattern + sheet 内自己的 NavigationStack,完全独立于外层
    // 任何 NavStack 状态;历史列表与 detail 都在 sheet 内 push,不再依赖
    // 外层 path / destination 注册顺序。这是 iOS 处理"全屏 modal 二级
    // 列表 + 详情"的最稳路径(Apple Mail / Notes / Reminders 的"标签"列表
    // 都走 sheet+inner NavStack)。
    @State private var showHistorySheet: Bool = false
    @State private var navPath = NavigationPath()
    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(client: SupabaseClient = supabase, isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: FinanceViewModel(client: client))
        self.isEmbedded = isEmbedded
    }

    /// Mirrors Web gate (`hasCapability(caps, 'finance_ops')` at page.tsx:44).
    /// iOS Phase 4 splits finance into more granular caps; here we accept
    /// either the workspace-level `finance_ops` OR any of the three AI
    /// finance caps so the gate matches AppModule's declared requirement.
    private var canAccess: Bool {
        let caps = RBACManager.shared.getEffectiveCapabilities(for: sessionManager.currentProfile)
        let required: [Capability] = [
            .finance_ops,
            .ai_finance_data_processing,
            .ai_finance_docs,
            .ai_finance_reports,
        ]
        return caps.contains(where: { required.contains($0) })
    }

    public var body: some View {
        Group {
            if isEmbedded {
                coreContent
            } else {
                NavigationStack(path: $navPath) { coreContent }
            }
        }
        .zyErrorBanner($viewModel.errorMessage)
    }

    private var coreContent: some View {
        Group {
            if !canAccess {
                BsEmptyState(
                    title: "无权访问",
                    systemImage: "lock",
                    description: "财务 AI 工作台仅对拥有财务相关能力的管理员开放。"
                )
            } else {
                content
            }
        }
        .navigationTitle("财务 AI 工作台")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canAccess {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // 改回纯 Button + sheet —— sheet 内嵌自己的 NavigationStack,
                    // 完全独立于外层 palette/dashboard 的 NavStack 状态。
                    Button {
                        Haptic.light()
                        showHistorySheet = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("处理历史")
                }
            }
        }
        .task {
            if canAccess { await viewModel.fetchHistory() }
        }
        .refreshable {
            if canAccess { await viewModel.fetchHistory() }
        }
        // FinanceAIRecord push 仍然走外层 NavStack(submitAIProcess 成功后
        // navPath.append 也是同一条),sheet 内的 history 列表自带子 NavStack
        // 走自己的 detail push,两条路径互不干扰。
        .navigationDestination(for: FinanceAIRecord.self) { record in
            FinanceRecordDetailView(record: record)
        }
        .sheet(isPresented: $showHistorySheet) {
            // 内嵌 NavigationStack 让 history → detail push 与外层完全
            // 解耦;sheet 自带 swipe-down 关闭,FinanceRecordDetailView
            // push 进来后还能继续 swipe-down 整个 sheet 关闭(iOS 原生)。
            NavigationStack {
                historyListPage
                    .navigationDestination(for: FinanceAIRecord.self) { record in
                        FinanceRecordDetailView(record: record)
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") {
                                Haptic.light()
                                showHistorySheet = false
                            }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                chainSelector
                inputSection
                chartsSection
                recentRecordsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }

    private var header: some View {
        HStack(spacing: BsSpacing.md) {
            Image(systemName: "wallet.pass")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: [BsColor.brandAzure, BsColor.brandMint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("财务 AI 工作台")
                    .font(BsTypography.cardTitle)
                    .foregroundStyle(BsColor.ink)
                Text("智能财务文档处理 · 结构化输出")
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer()
        }
    }

    // MARK: - Chain selector

    private var chainSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("任务类型")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BsColor.inkMuted)
            HStack(spacing: 10) {
                ForEach(FinanceChain.allCases) { chain in
                    Button {
                        // Haptic removed: 用户反馈 chain 切换过密震动
                        viewModel.selectedChain = chain
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: chain.iconName)
                                    .font(.callout.weight(.semibold))
                                Spacer()
                            }
                            Text(chain.shortLabel)
                                .font(.footnote.weight(.bold))
                            Text(chain.description)
                                .font(.caption2)
                                .foregroundStyle(BsColor.inkMuted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(viewModel.selectedChain == chain
                                      ? BsColor.brandAzure.opacity(0.12)
                                      : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(viewModel.selectedChain == chain
                                        ? BsColor.brandAzure
                                        : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Input section
    // POST /api/mobile/finance/ai-process；Web 等价实现：
    // aiDocumentOrganize / aiReportSummarize / aiDataProcess in
    // src/lib/actions/finance-ai.ts.

    @ViewBuilder
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(BsColor.brandAzure)  // TODO(batch-3): evaluate .purple → brandAzure
                Text("AI 处理")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            // 下拉：根据 chain 切换参数
            switch viewModel.selectedChain {
            case .documentOrganize:
                Picker("文档类型", selection: $viewModel.docType) {
                    ForEach(FinanceDocType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.menu)
                // Haptic removed: 用户反馈 picker 切换过密震动
            case .reportSummarize:
                Picker("报表类型", selection: $viewModel.reportType) {
                    ForEach(FinanceReportType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.menu)
                // Haptic removed: 用户反馈 picker 切换过密震动
            case .dataProcess:
                Picker("处理类型", selection: $viewModel.processType) {
                    ForEach(FinanceProcessType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.menu)
                // Haptic removed: 用户反馈 picker 切换过密震动
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(minHeight: 140)
                TextEditor(text: $viewModel.inputText)
                    .frame(minHeight: 140)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                if viewModel.inputText.isEmpty {
                    Text(placeholderText)
                        .font(.footnote)
                        .foregroundStyle(BsColor.inkFaint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }

            Button {
                Haptic.medium()
                Task {
                    if let record = await viewModel.submitAIProcess() {
                        // 程序式 push 到 detail —— 走同一条 value-based
                        // navigationDestination,不会和 list 的 NavigationLink 互相
                        // 抢。embedded 模式下外层 NavStack 不由我们持有,这里把
                        // path 推空会被 SwiftUI 忽略,最坏就是不自动跳转 —— 用户
                        // 仍然能从列表最新一条进入,不是 regression。
                        if !isEmbedded {
                            navPath.append(record)
                        }
                    }
                }
            } label: {
                Text(viewModel.isSubmitting ? "AI 处理中…" : "开始 AI 处理")
            }
            .buttonStyle(BsPrimaryButtonStyle(size: .large, isLoading: viewModel.isSubmitting))
            .disabled(
                viewModel.isSubmitting
                || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .padding(BsSpacing.md + 2)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.lg - 2, style: .continuous)
                .fill(BsColor.brandAzure.opacity(0.06))
        )
    }

    private var placeholderText: String {
        switch viewModel.selectedChain {
        case .documentOrganize: return "粘贴发票 / 合同 / 报销单等文档原文"
        case .reportSummarize: return "粘贴财务报表 / 经营分析文本"
        case .dataProcess: return "粘贴需要分类 / 提取 / 校验的数据行"
        }
    }

    // MARK: - Charts section

    @ViewBuilder
    private var chartsSection: some View {
        switch viewModel.selectedChain {
        case .dataProcess:
            chartConfidenceBuckets
        case .reportSummarize:
            chartMetricFrequency
        case .documentOrganize:
            chartDocumentStatus
        }
    }

    private var chartConfidenceBuckets: some View {
        let buckets = viewModel.confidenceBuckets
        return VStack(alignment: .leading, spacing: 8) {
            Text("处理置信度分布")
                .font(.footnote.weight(.semibold))
            if buckets.isEmpty {
                emptyChartPlaceholder(text: "暂无数据处理记录")
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("区间", bucket.label),
                        y: .value("条数", bucket.count)
                    )
                    .foregroundStyle(by: .value("区间", bucket.label))
                    .annotation(position: .top) {
                        Text("\(bucket.count)")
                            .font(.caption2)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var chartMetricFrequency: some View {
        let metrics = viewModel.metricFrequency
        return VStack(alignment: .leading, spacing: 8) {
            Text("关键指标出现频次 (Top 6)")
                .font(.footnote.weight(.semibold))
            if metrics.isEmpty {
                emptyChartPlaceholder(text: "暂无报表整理记录")
            } else {
                Chart(metrics) { m in
                    BarMark(
                        x: .value("次数", m.count),
                        y: .value("指标", m.name)
                    )
                    .foregroundStyle(BsColor.brandAzure.gradient)
                }
                .frame(height: CGFloat(metrics.count) * 32 + 24)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var chartDocumentStatus: some View {
        // Document chain doesn't ship numeric metrics by default; show a
        // rolling count by month so the Charts area never stays blank when
        // there IS history. Empty-state still falls through below.
        let docs = viewModel.records.filter { $0.chainEnum == .documentOrganize }
        let byDay = Dictionary(grouping: docs) { record in
            Calendar.current.startOfDay(for: record.createdAt)
        }
        let points = byDay
            .map { (date, rows) in DocPoint(date: date, count: rows.count) }
            .sorted { $0.date < $1.date }

        return VStack(alignment: .leading, spacing: 8) {
            Text("近期文档整理趋势")
                .font(.footnote.weight(.semibold))
            if points.isEmpty {
                emptyChartPlaceholder(text: "暂无文档整理记录")
            } else {
                Chart(points) { p in
                    LineMark(
                        x: .value("日期", p.date),
                        y: .value("次数", p.count)
                    )
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("日期", p.date),
                        y: .value("次数", p.count)
                    )
                }
                .frame(height: 180)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private struct DocPoint: Identifiable, Hashable {
        var id: Date { date }
        let date: Date
        let count: Int
    }

    private func emptyChartPlaceholder(text: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.title3)
                    .foregroundStyle(BsColor.inkFaint)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }
            .padding(.vertical, 16)
            Spacer()
        }
    }

    // MARK: - Recent records

    private var recentRecordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.selectedChain.displayName + " · 最近 5 条")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button {
                    Haptic.light()
                    showHistorySheet = true
                } label: {
                    Text("全部历史")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BsColor.brandAzure)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoading && viewModel.records.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if viewModel.filteredRecords.isEmpty {
                Text("暂无 \(viewModel.selectedChain.displayName) 记录")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(viewModel.filteredRecords.prefix(5))) { record in
                        NavigationLink(value: record) {
                            FinanceRecordRow(record: record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - History list page (pushed, NOT sheet)
    //
    // 走外层 NavigationStack 的 push,所以不需要再嵌一层 NavigationStack,
    // 也不需要再注册一遍 .navigationDestination(for: FinanceAIRecord.self)
    // —— 父 view 已经注册了。这里就是纯内容 + navigationTitle。

    @ViewBuilder
    private var historyListPage: some View {
        Group {
            if viewModel.records.isEmpty {
                BsEmptyState(
                    title: "暂无处理记录",
                    systemImage: "tray",
                    description: "历史记录仅显示当前账号发起的 AI 处理。"
                )
            } else {
                List {
                    ForEach(viewModel.records) { record in
                        NavigationLink(value: record) {
                            FinanceRecordRow(record: record, compact: true)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("处理历史")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.fetchHistory()
        }
    }
}

// MARK: - Record Row

private struct FinanceRecordRow: View {
    let record: FinanceAIRecord
    var compact: Bool = false

    private var chainLabel: String {
        record.chainEnum?.displayName ?? record.chain
    }

    private var chainColor: Color {
        switch record.chainEnum {
        case .documentOrganize: return BsColor.brandAzure
        case .reportSummarize: return BsColor.brandMint
        case .dataProcess: return BsColor.brandCoral
        case .none: return BsColor.inkMuted
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(chainLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(chainColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(chainColor.opacity(0.14), in: Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(record.inputSummary?.isEmpty == false
                     ? record.inputSummary!
                     : "(无输入摘要)")
                    .font(.footnote)
                    .lineLimit(2)
                Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer()
            if !compact {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkFaint)
            }
        }
        .padding(compact ? 0 : 12)
        .background(
            compact ? Color.clear : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}
