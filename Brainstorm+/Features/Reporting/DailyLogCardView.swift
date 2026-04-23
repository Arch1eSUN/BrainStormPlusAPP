import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch B.1 — Daily log card.
//
// Mirrors the historical-row chips in `src/app/dashboard/daily/page.tsx`
// (≈ L284-345): mood pill, content, progress/blockers tags, and
// approval-status badge for historical rows.
// ══════════════════════════════════════════════════════════════════

public struct DailyLogCardView: View {
    public let log: DailyLog

    public init(log: DailyLog) {
        self.log = log
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(log.date, style: .date)
                    .font(.headline)
                Spacer()
                if let status = log.approvalStatus {
                    approvalBadge(status)
                }
                if let mood = log.mood {
                    moodTag(mood: mood)
                }
            }

            Text(log.content)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(4)

            if log.progress != nil || log.blockers != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let p = log.progress, !p.isEmpty {
                        tag(text: "✓ \(p)", color: .green)
                    }
                    if let b = log.blockers, !b.isEmpty {
                        tag(text: "⚠ \(b)", color: .red)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
    }

    @ViewBuilder
    private func moodTag(mood: DailyLog.Mood) -> some View {
        HStack(spacing: 4) {
            Text(mood.emoji)
            Text(mood.displayLabel)
                .font(.caption2)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func approvalBadge(_ status: ReportApprovalStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .pending:  return ("待审批", .orange)
            case .approved: return ("已通过", .green)
            case .rejected: return ("已拒绝", .red)
            }
        }()
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func tag(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.xs, style: .continuous))
    }
}

// ══════════════════════════════════════════════════════════════════
// Weekly report card — new in B.1 to pair with the edit view.
// ══════════════════════════════════════════════════════════════════

public struct WeeklyReportCardView: View {
    public let report: WeeklyReport

    public init(report: WeeklyReport) {
        self.report = report
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(weekRangeText)
                    .font(.headline)
                Spacer()
                if let status = report.approvalStatus {
                    statusBadge(raw: status.rawValue, palette: .report)
                }
                statusBadge(raw: report.status.rawValue, palette: .lifecycle)
            }

            if let summary = report.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }

            if let feedback = report.feedback, !feedback.isEmpty {
                Text("反馈：\(feedback)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
    }

    private var weekRangeText: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: report.weekStart) ?? report.weekStart
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return "\(f.string(from: report.weekStart)) — \(f.string(from: end))"
    }

    private enum Palette { case report, lifecycle }

    @ViewBuilder
    private func statusBadge(raw: String, palette: Palette) -> some View {
        let (label, color): (String, Color) = {
            switch palette {
            case .report:
                switch raw {
                case "pending":  return ("待审批", .orange)
                case "approved": return ("已通过", .green)
                case "rejected": return ("已拒绝", .red)
                default:         return (raw, .gray)
                }
            case .lifecycle:
                switch raw {
                case "draft":     return ("草稿", .gray)
                case "submitted": return ("已提交", .blue)
                case "reviewed":  return ("已审阅", .green)
                default:          return (raw, .gray)
                }
            }
        }()
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
