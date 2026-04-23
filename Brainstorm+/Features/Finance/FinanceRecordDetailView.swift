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
                    .foregroundStyle(.secondary)
            }
            if let model = record.aiModel, !model.isEmpty {
                Text("模型：\(model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let summary = record.inputSummary, !summary.isEmpty {
                Divider().padding(.vertical, 4)
                Text("输入摘要")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.primary)
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
                    .foregroundStyle(.blue)
                Text(text)
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            )
        }
    }

    private struct KeyMetricsCard: View {
        let metrics: [FinanceParsedOutput.KeyMetric]

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("关键指标", systemImage: "chart.bar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(metrics) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(m.value)
                                    .font(.footnote.weight(.bold))
                                trendIcon(m.trend)
                            }
                            if let note = m.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
                    .fill(Color.green.opacity(0.08))
            )
        }

        @ViewBuilder
        private func trendIcon(_ trend: String?) -> some View {
            switch trend {
            case "up":
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
            case "down":
                Image(systemName: "arrow.down.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
            case "flat":
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.blue)
                LazyVStack(spacing: 6) {
                    ForEach(items) { item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.description)
                                    .font(.footnote)
                                    .lineLimit(2)
                                Text(item.category)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
                    .fill(Color.blue.opacity(0.08))
            )
        }
    }

    private struct DataRecordsCard: View {
        let records: [FinanceParsedOutput.DataRecord]

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label("处理记录", systemImage: "tablecells")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.purple)
                LazyVStack(spacing: 6) {
                    ForEach(records) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("#\(r.index)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
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
                    .fill(Color.purple.opacity(0.08))
            )
        }

        private func confidenceColor(_ v: Int) -> Color {
            if v >= 80 { return .green }
            if v >= 60 { return .orange }
            return .red
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
                        color: .green,
                        items: parsed.highlights
                    )
                }
                if !parsed.concerns.isEmpty {
                    BulletBlock(
                        title: "隐忧",
                        iconName: "exclamationmark.triangle",
                        color: .orange,
                        items: parsed.concerns
                    )
                }
                if !parsed.riskFlags.isEmpty {
                    BulletBlock(
                        title: "风险标记",
                        iconName: "exclamationmark.octagon.fill",
                        color: .red,
                        items: parsed.riskFlags
                    )
                }
                if !parsed.actionItems.isEmpty {
                    BulletBlock(
                        title: "待办事项",
                        iconName: "checklist",
                        color: .blue,
                        items: parsed.actionItems
                    )
                }
                if !parsed.recommendations.isEmpty {
                    BulletBlock(
                        title: "建议",
                        iconName: "lightbulb",
                        color: .purple,
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
                    .foregroundStyle(Color.accentColor)
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.accentColor, in: Circle())
                        Text(step)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
        }
    }

    private struct RawTextCard: View {
        let text: String
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label("原始输出", systemImage: "curlybraces")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
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
