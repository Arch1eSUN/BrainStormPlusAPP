import SwiftUI

public struct PayrollCardView: View {
    public let payroll: PayrollRecord
    
    public init(payroll: PayrollRecord) {
        self.payroll = payroll
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(payroll.period)
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                statusTag(status: payroll.status)
            }
            
            VStack(spacing: 8) {
                row(title: "Base Salary", amount: payroll.baseSalary)
                
                if let allowances = payroll.allowances, allowances > 0 {
                    row(title: "Allowances", amount: allowances)
                }
                
                if payroll.bonus > 0 {
                    row(title: "Bonus", amount: payroll.bonus)
                }
                
                if payroll.deductions > 0 {
                    row(title: "Total Deductions", amount: payroll.deductions, isNegative: true)
                }
                
                if let late = payroll.latePenalty, late > 0 {
                    row(title: " • Late Penalty", amount: late, isNegative: true, isSub: true)
                }
                
                if let early = payroll.earlyLeavePenalty, early > 0 {
                    row(title: " • Early Leave Penalty", amount: early, isNegative: true, isSub: true)
                }
                
                if let missed = payroll.missedClockPenalty, missed > 0 {
                    row(title: " • Missed Clock Penalty", amount: missed, isNegative: true, isSub: true)
                }
                
                if let absent = payroll.absentPenalty, absent > 0 {
                    row(title: " • Absent Penalty", amount: absent, isNegative: true, isSub: true)
                }
                
                if let leaveM = payroll.leaveDeduction, leaveM > 0 {
                    row(title: " • Unpaid Leave", amount: leaveM, isNegative: true, isSub: true)
                }
                
                Divider()
                    .background(Color.secondary.opacity(0.3))
                
                HStack {
                    if let attDays = payroll.attendanceDays {
                       Text("Net Pay (\(attDays) attendance days)")
                           .font(.footnote)
                           .foregroundColor(.secondary)
                    } else {
                       Text("Net Pay")
                           .font(.headline)
                           .fontWeight(.semibold)
                    }
                    Spacer()
                    Text("¥\(payroll.netPay as NSNumber, formatter: currencyFormatter)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }
            
            if let paidAt = payroll.paidAt {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Paid on \(paidAt, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Text("Pre-calculation. Final salary may change based on KPIs.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private func row(title: String, amount: Decimal, isNegative: Bool = false, isSub: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(isSub ? .secondary.opacity(0.8) : .secondary)
            Spacer()
            Text("\(isNegative ? "-" : "+")¥\(amount as NSNumber, formatter: currencyFormatter)")
                .font(.subheadline)
                .foregroundColor(isNegative ? .red : .primary)
        }
    }
    
    @ViewBuilder
    private func statusTag(status: PayrollRecord.PayrollStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor(status).opacity(0.2))
            .foregroundColor(statusColor(status))
            .clipShape(Capsule())
    }
    
    private func statusColor(_ status: PayrollRecord.PayrollStatus) -> Color {
        switch status {
        case .draft: return .gray
        case .processing: return .blue
        case .paid, .confirmed: return .green
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
