import Foundation

public struct PayrollRecord: Identifiable, Codable, Hashable {
    public let id: UUID
    public let userId: UUID
    public let period: String
    public let baseSalary: Decimal
    public let allowances: Decimal?
    public let deductions: Decimal
    public let bonus: Decimal
    public let netPay: Decimal
    public let status: PayrollStatus
    public let paidAt: Date?
    public let createdAt: Date?
    public let updatedAt: Date?
    
    // Extracted attendance & penalty fields
    public let attendanceDays: Int?
    public let latePenalty: Decimal?
    public let earlyLeavePenalty: Decimal?
    public let missedClockPenalty: Decimal?
    public let absentPenalty: Decimal?
    public let leaveDeduction: Decimal?

    public enum PayrollStatus: String, Codable, Hashable {
        case draft = "draft"
        case processing = "processing"
        case paid = "paid"
        case confirmed = "confirmed"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case period
        case baseSalary = "base_salary"
        case allowances
        case deductions
        case bonus
        case netPay = "net_pay"
        case status
        case paidAt = "paid_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case attendanceDays = "attendance_days"
        case latePenalty = "late_penalty"
        case earlyLeavePenalty = "early_leave_penalty"
        case missedClockPenalty = "missed_clock_penalty"
        case absentPenalty = "absent_penalty"
        case leaveDeduction = "leave_deduction"
    }
}
