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
    // Bug-fix(财务历史闪一下 + 返回后才显示):
    // 之前用 .sheet(isPresented:) 嵌内层 NavigationStack 渲染历史列表,在
    // isEmbedded 模式下(从 Command Palette / Dashboard 进入)外层已有
    // NavigationStack —— sheet 内的 NavigationLink push 经常被外层 stack 抢断,
    // 表现就是 sheet 一闪而过、再返回时 sheet 才"补"出来。
    // 修法:历史列表改成同栈 push (走外层或自己的 NavigationStack),完全消除
    // sheet ↔ NavStack 双层冲突。`historyRoute` 是 navigationDestination 的 tag,
    // 用枚举而不是 Bool 是为了 Hashable + 未来还能扩展子分类。
    @State private var navPath = NavigationPath()
    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    /// History 路由 tag。NavigationLink(value:) push 这条 → 触发
    /// `.navigationDestination(for: HistoryRoute.self)` 渲染全屏历史列表。
    private enum HistoryRoute: Hashable { case all }

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
                    // 用 NavigationLink(value:) 替换原来的 sheet trigger ——
                    // push 走外层(或自己持有的) NavigationStack,跟 detail push
                    // 共用同一条 path,iOS 不会再出现"sheet present 中 push 被
                    // 抢断"的二次 dispatch。
                    NavigationLink(value: HistoryRoute.all) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    // Haptic removed: 用户反馈 toolbar 按钮过密震动
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
        // 单一 value-based destination 注册一次,同时承接 record push 和
        // history list push。两个 type 都是 Hashable,SwiftUI 按 type 路由,
        // 不会冲突。
        .navigationDestination(for: FinanceAIRecord.self) { record in
            FinanceRecordDetailView(record: record)
        }
        .navigationDestination(for: HistoryRoute.self) { _ in
            historyListPage
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
                NavigationLink(value: HistoryRoute.all) {
                    Text("全部历史")
                        .font(.caption.weight(.semibold))
                }
                // Haptic removed: 用户反馈 navigation link 过密震动
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
