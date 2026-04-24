import SwiftUI

// ══════════════════════════════════════════════════
// BrainStorm+ iOS — Finance AI Record Detail
//
// Mirrors the "Result Display" block of Web
// `src/app/dashboard/finance/page.tsx` L509-720.
// Pure read-only rendering of `ai_work_records.output_json` for a single
// finance record (structured output: summary / key metrics / financial
// items / data records / highlights / concerns / risk flags / action
// items / recommendations / suggested next steps / raw text fallback).
// ══════════════════════════════════════════════════

public struct FinanceRecordDetailView: View {
    public let record: FinanceAIRecord

    public init(record: FinanceAIRecord) {
        self.record = record
    }

    private var parsed: FinanceParsedOutput? { record.parsedOutput }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if let p = parsed, p.hasAnyContent {
                    if let s = p.summary, !s.isEmpty {
                        SummaryCard(text: s)
                    }
                    if !p.keyMetrics.isEmpty {
                        KeyMetricsCard(metrics: p.keyMetrics)
                    }
                    if !p.financialItems.isEmpty {
                        FinancialItemsCard(items: p.financialItems)
                    }
                    if !p.records.isEmpty {
                        DataRecordsCard(records: p.records)
                    }
                    InsightsGrid(parsed: p)
                    if !p.suggestedNextSteps.isEmpty {
                        NextStepsCard(steps: p.suggestedNextSteps)
                    }
                    if let raw = p.rawText, !raw.isEmpty {
                        RawTextCard(text: raw)
                    }
                } else {
                    ContentUnavailableView(
                        "输出为空",
                        systemImage: "tray",
                        description: Text("该记录未包含可解析的结构化输出。")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle(record.chainEnum?.displayName ?? "处理详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.chainEnum?.displayName ?? record.chain)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(record.createdAt, format: .dateTime
                    .year().month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkMuted)
            }
            if let model = record.aiModel, !model.isEmpty {
                Text("模型：\(model)")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
            }
            if let summary = record.inputSummary, !summary.isEmpty {
                Divider().padding(.vertical, 4)
                Text("输入摘要")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BsColor.inkMuted)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(BsColor.ink)
                    .lineLimit(6)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Cards

    private struct SummaryCard: View {
        let text: String
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("摘要", systemImage: "text.alignleft")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BsColor.brandAzure)
                Text(text)
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BsColor.brandAzure.opacity(0.08))
            )
        }
    }

    private struct KeyMetricsCard: View {
        let metrics: [FinanceParsedOutput.KeyMetric]

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("关键指标", systemImage: "chart.bar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BsColor.success)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(metrics) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.name)
                                .font(.caption2)
                                .foregroundStyle(BsColor.inkMuted)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(m.value)
                                    .font(.footnote.weight(.bold))
                                trendIcon(m.trend)
                            }
                            if let note = m.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(BsColor.inkMuted)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BsColor.success.opacity(0.08))
            )
        }

        @ViewBuilder
        private func trendIcon(_ trend: String?) -> some View {
            switch trend {
            case "up":
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BsColor.success)
            case "down":
                Image(systemName: "arrow.down.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BsColor.danger)
            case "flat":
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BsColor.inkMuted)
            default: EmptyView()
            }
        }
    }

    private struct FinancialItemsCard: View {
        let items: [FinanceParsedOutput.FinancialItem]
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("财务条目", systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BsColor.brandAzure)
                LazyVStack(spacing: 6) {
                    ForEach(items) { item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.description)
                                    .font(.footnote)
                                    .lineLimit(2)
                                Text(item.category)
                                    .font(.caption2)
                                    .foregroundStyle(BsColor.inkMuted)
                            }
                            Spacer()
                            Text(formatAmount(item.amount))
                                .font(.footnote.weight(.bold))
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BsColor.brandAzure.opacity(0.08))
            )
        }
    }

    private struct DataRecordsCard: View {
        let records: [FinanceParsedOutput.DataRecord]

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("处理记录", systemImage: "tablecells")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BsColor.brandAzure)  // TODO(batch-3): evaluate .purple → brandAzure
                LazyVStack(spacing: 6) {
                    ForEach(records) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("#\(r.index)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(BsColor.inkMuted)
                                Spacer()
                                Text("\(r.confidence)%")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(confidenceColor(r.confidence), in: Capsule())
                            }
                            HStack(alignment: .top) {
                                Text("原始：\(r.original)")
                                    .font(.caption)
                                    .foregroundStyle(BsColor.inkMuted)
                                    .lineLimit(2)
                            }
                            HStack(alignment: .top) {
                                Text("结果：\(r.result)")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                            }
                            if let note = r.notes, !note.isEmpty {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(BsColor.inkMuted)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(.systemBackground))
                        )
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BsColor.brandAzure.opacity(0.08))  // TODO(batch-3): evaluate .purple → brandAzure
            )
        }

        private func confidenceColor(_ v: Int) -> Color {
            if v >= 80 { return BsColor.success }
            if v >= 60 { return BsColor.warning }
            return BsColor.danger
        }
    }

    private struct InsightsGrid: View {
        let parsed: FinanceParsedOutput

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                if !parsed.highlights.isEmpty {
                    BulletBlock(
                        title: "亮点",
                        iconName: "checkmark.seal.fill",
                        color: BsColor.success,
                        items: parsed.highlights
                    )
                }
                if !parsed.concerns.isEmpty {
                    BulletBlock(
                        title: "隐忧",
                        iconName: "exclamationmark.triangle",
                        color: BsColor.warning,
                        items: parsed.concerns
                    )
                }
                if !parsed.riskFlags.isEmpty {
                    BulletBlock(
                        title: "风险标记",
                        iconName: "exclamationmark.octagon.fill",
                        color: BsColor.danger,
                        items: parsed.riskFlags
                    )
                }
                if !parsed.actionItems.isEmpty {
                    BulletBlock(
                        title: "待办事项",
                        iconName: "checklist",
                        color: BsColor.brandAzure,
                        items: parsed.actionItems
                    )
                }
                if !parsed.recommendations.isEmpty {
                    BulletBlock(
                        title: "建议",
                        iconName: "lightbulb",
                        color: BsColor.brandAzure,  // TODO(batch-3): evaluate .purple → brandAzure
                        items: parsed.recommendations
                    )
                }
            }
        }
    }

    private struct BulletBlock: View {
        let title: String
        let iconName: String
        let color: Color
        let items: [String]

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(color)
                        Text(text).font(.footnote)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.08))
            )
        }
    }

    private struct NextStepsCard: View {
        let steps: [String]
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("建议下一步操作", systemImage: "arrow.right.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BsColor.brandAzure)
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(BsColor.brandAzure, in: Circle())
                        Text(step)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BsColor.brandAzure.opacity(0.08))
            )
        }
    }

    private struct RawTextCard: View {
        let text: String
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label("原始输出", systemImage: "curlybraces")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BsColor.inkMuted)
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
}

// MARK: - Amount formatter (CNY, 千分位)

/// Apply Chinese-locale number formatting with a ¥ prefix when the AI
/// output emits a bare numeric value. If the string already embeds a
/// currency symbol or punctuation (e.g. "¥12,345.00", "USD 1,000"), leave
/// it untouched so we don't mangle foreign currencies.
private let financeAmountFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "zh_CN")
    f.groupingSeparator = ","
    f.usesGroupingSeparator = true
    f.maximumFractionDigits = 2
    f.minimumFractionDigits = 0
    return f
}()

func formatAmount(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return raw }
    // Strip a leading ¥ / CNY / RMB so we can re-emit a consistent prefix
    let stripped = trimmed
        .replacingOccurrences(of: "¥", with: "")
        .replacingOccurrences(of: "￥", with: "")
        .replacingOccurrences(of: "CNY", with: "", options: .caseInsensitive)
        .replacingOccurrences(of: "RMB", with: "", options: .caseInsensitive)
        .replacingOccurrences(of: ",", with: "")
        .trimmingCharacters(in: .whitespaces)
    if let n = Double(stripped),
       let s = financeAmountFormatter.string(from: NSNumber(value: n)) {
        return "¥\(s)"
    }
    return raw
}
