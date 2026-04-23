import SwiftUI

public struct PayrollCardView: View {
    public let payroll: PayrollRecord

    public init(payroll: PayrollRecord) {
        self.payroll = payroll
    }

    public var body: some View {
        BsCard(variant: .flat, padding: .medium) {
            VStack(spacing: BsSpacing.lg) {
                HStack {
                    Text(payroll.period)
                        .font(BsTypography.cardTitle)
                        .foregroundStyle(BsColor.ink)
                    Spacer()
                    statusTag(status: payroll.status)
                }

                VStack(spacing: BsSpacing.sm) {
                    row(title: "基本工资", amount: payroll.baseSalary)

                    if let allowances = payroll.allowances, allowances > 0 {
                        row(title: "津贴补助", amount: allowances)
                    }

                    if payroll.bonus > 0 {
                        row(title: "奖金", amount: payroll.bonus)
                    }

                    if payroll.deductions > 0 {
                        row(title: "扣款合计", amount: payroll.deductions, isNegative: true)
                    }

                    if let late = payroll.latePenalty, late > 0 {
                        row(title: " • 迟到扣款", amount: late, isNegative: true, isSub: true)
                    }

                    if let early = payroll.earlyLeavePenalty, early > 0 {
                        row(title: " • 早退扣款", amount: early, isNegative: true, isSub: true)
                    }

                    if let missed = payroll.missedClockPenalty, missed > 0 {
                        row(title: " • 漏打卡扣款", amount: missed, isNegative: true, isSub: true)
                    }

                    if let absent = payroll.absentPenalty, absent > 0 {
                        row(title: " • 缺勤扣款", amount: absent, isNegative: true, isSub: true)
                    }

                    if let leaveM = payroll.leaveDeduction, leaveM > 0 {
                        row(title: " • 无薪假扣款", amount: leaveM, isNegative: true, isSub: true)
                    }

                    Divider()
                        .background(BsColor.borderSubtle)

                    HStack {
                        if let attDays = payroll.attendanceDays {
                            Text("实发工资（出勤 \(attDays) 天）")
                                .font(BsTypography.captionSmall)
                                .foregroundStyle(BsColor.inkMuted)
                        } else {
                            Text("实发工资")
                                .font(BsTypography.cardTitle)
                                .foregroundStyle(BsColor.ink)
                        }
                        Spacer()
                        Text("¥\(payroll.netPay as NSNumber, formatter: currencyFormatter)")
                            .font(BsTypography.statMedium)
                            .foregroundStyle(BsColor.ink)
                    }
                }

                if let paidAt = payroll.paidAt {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(BsColor.success)
                        Text("发放于 \(paidAt, style: .date)")
                            .font(BsTypography.caption)
                            .foregroundStyle(BsColor.inkMuted)
                        Spacer()
                    }
                } else {
                    Text("此为预估金额，最终薪资可能根据 KPI 等指标调整。")
                        .font(BsTypography.meta)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
        }
    }

    private func row(title: String, amount: Decimal, isNegative: Bool = false, isSub: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(BsTypography.bodySmall)
                .foregroundStyle(isSub ? BsColor.inkFaint : BsColor.inkMuted)
            Spacer()
            Text("\(isNegative ? "-" : "+")¥\(amount as NSNumber, formatter: currencyFormatter)")
                .font(BsTypography.statSmall)
                .foregroundStyle(isNegative ? BsColor.danger : BsColor.ink)
        }
    }

    @ViewBuilder
    private func statusTag(status: PayrollRecord.PayrollStatus) -> some View {
        Text(statusLabel(status))
            .font(BsTypography.meta)
            .padding(.horizontal, BsSpacing.sm + 2)
            .padding(.vertical, BsSpacing.xs + 2)
            .background(statusColor(status).opacity(0.2))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusLabel(_ status: PayrollRecord.PayrollStatus) -> String {
        switch status {
        case .draft: return "草稿"
        case .processing: return "处理中"
        case .paid: return "已发放"
        case .confirmed: return "已确认"
        }
    }

    private func statusColor(_ status: PayrollRecord.PayrollStatus) -> Color {
        switch status {
        case .draft: return BsColor.inkMuted
        case .processing: return BsColor.brandAzure
        case .paid, .confirmed: return BsColor.success
        }
    }

    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
