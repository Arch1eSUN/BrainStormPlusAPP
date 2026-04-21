import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Procurement submit ViewModel.
//
// Parity target: Web `submitProcurementRequest`
// (src/lib/actions/approval-requests.ts:220-303) +
// `src/components/approval/procurement-form.tsx`.
//
// Unit + total price both serialize to cents. The form computes
// `totalYuan = unitYuan * quantity` for display, and we send both to
// the RPC so the server can validate each independently (DB CHECK
// constraints require both > 0). Client-computed total keeps the UI
// reactive; server independently re-validates.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class ProcurementSubmitViewModel: ObservableObject {
    // MARK: - Form state

    @Published public var procurementType: ProcurementType = .other
    @Published public var itemDescription: String = ""
    @Published public var vendor: String = ""
    @Published public var quantity: Int = 1
    @Published public var unitPriceYuan: Decimal = 0
    @Published public var currency: String = "CNY"
    @Published public var userOrDepartment: String = ""
    @Published public var purpose: String = ""
    @Published public var alternatives: String = ""
    @Published public var justification: String = ""
    @Published public var budgetAvailable: Bool = true
    @Published public var expectedPurchaseDate: Date? = nil
    @Published public var priority: RequestPriority = .medium
    @Published public var businessReason: String = ""
    @Published public var relatedProject: String = ""
    @Published public var attachments: [ApprovalAttachment] = []

    // MARK: - Submit state

    @Published public private(set) var isSubmitting: Bool = false
    @Published public var errorMessage: String?
    @Published public private(set) var createdRequestId: UUID?

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Derived

    /// Client total = quantity × unit. Displayed under the quantity
    /// field so the user confirms the amount they're requesting. Kept
    /// as Decimal to avoid FP drift on values like 19.99 × 3.
    public var totalYuan: Decimal {
        unitPriceYuan * Decimal(quantity)
    }

    public var canSubmit: Bool {
        guard !itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !userOrDepartment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !justification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard quantity > 0 else { return false }
        guard unitPriceYuan > 0 else { return false }
        return !isSubmitting
    }

    // MARK: - Submit

    @discardableResult
    public func submit() async -> Bool {
        let trimmedItem = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = userOrDepartment.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedJust = justification.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedItem.isEmpty else {
            errorMessage = "请填写采购项目"
            return false
        }
        guard !trimmedVendor.isEmpty else {
            errorMessage = "请填写供应商"
            return false
        }
        guard !trimmedUser.isEmpty else {
            errorMessage = "请填写使用人/使用部门"
            return false
        }
        guard !trimmedPurpose.isEmpty else {
            errorMessage = "请填写采购用途"
            return false
        }
        guard !trimmedJust.isEmpty else {
            errorMessage = "请填写采购理由"
            return false
        }
        guard quantity > 0 else {
            errorMessage = "数量必须大于 0"
            return false
        }
        guard unitPriceYuan > 0 else {
            errorMessage = "单价必须大于 0"
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let unitCents = Self.yuanToCents(unitPriceYuan)
        let totalCents = Self.yuanToCents(totalYuan)

        let trimmedAlt = alternatives.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBusinessReason = businessReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelated = relatedProject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedDateStr = expectedPurchaseDate.map { Self.yyyyMMdd.string(from: $0) }

        let input = ProcurementSubmitInput(
            procurementType: procurementType,
            itemDescription: trimmedItem,
            vendor: trimmedVendor,
            quantity: quantity,
            unitPriceCents: unitCents,
            totalPriceCents: totalCents,
            currency: trimmedCurrency.isEmpty ? nil : trimmedCurrency,
            userOrDepartment: trimmedUser,
            purpose: trimmedPurpose,
            alternatives: trimmedAlt.isEmpty ? nil : trimmedAlt,
            justification: trimmedJust,
            budgetAvailable: budgetAvailable,
            expectedPurchaseDate: expectedDateStr,
            priority: priority,
            businessReason: trimmedBusinessReason.isEmpty ? nil : trimmedBusinessReason,
            relatedProject: trimmedRelated.isEmpty ? nil : trimmedRelated,
            attachments: attachments
        )

        do {
            let id: UUID = try await client
                .rpc("approvals_submit_procurement", params: input)
                .execute()
                .value
            self.createdRequestId = id
            return true
        } catch {
            self.errorMessage = prettyApprovalRPCError(error)
            return false
        }
    }

    // MARK: - Helpers

    private static func yuanToCents(_ yuan: Decimal) -> Int {
        NSDecimalNumber(decimal: yuan)
            .multiplying(by: 100)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))
            .intValue
    }

    private static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
