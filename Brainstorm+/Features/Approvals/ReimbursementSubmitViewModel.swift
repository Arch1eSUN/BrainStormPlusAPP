import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Reimbursement submit ViewModel.
//
// Parity target: Web `submitReimbursementRequest`
// (src/lib/actions/approval-requests.ts:139-216) +
// `src/components/approval/reimbursement-form.tsx`.
//
// Cents convention: the form binds to `amountYuan: Decimal`. On submit
// we convert via `NSDecimalNumber(decimal:).multiplying(by: 100)` and
// round to the nearest integer cent, matching Web's `Math.round(yuan
// * 100)`. Using `Decimal` rather than `Double` avoids FP drift on
// values like 19.99 that would otherwise produce 1998 cents instead
// of 1999.
//
// Attachments / receipt URLs: this sprint ships with empty arrays —
// the iOS file-upload surface is deferred (tracked as 4.x polish).
// The RPC accepts `COALESCE(p_receipt_urls, '[]'::jsonb)` so empty is
// fine; `receipt_uploaded` just computes `false`.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class ReimbursementSubmitViewModel: ObservableObject {
    // MARK: - Form state

    @Published public var itemDescription: String = ""
    @Published public var category: ReimbursementCategory = .other
    @Published public var purchaseDate: Date = Date()
    @Published public var amountYuan: Decimal = 0
    @Published public var currency: String = "CNY"
    @Published public var merchant: String = ""
    @Published public var paymentMethod: PaymentMethod = .personalCash
    @Published public var purpose: String = ""
    @Published public var priority: RequestPriority = .medium
    @Published public var businessReason: String = ""
    @Published public var relatedProject: String = ""
    // Left empty until iOS upload surface is built (4.x polish).
    @Published public var attachments: [ApprovalAttachment] = []
    @Published public var receiptUrls: [String] = []

    // MARK: - Submit state

    @Published public private(set) var isSubmitting: Bool = false
    @Published public var errorMessage: String?
    @Published public private(set) var createdRequestId: UUID?

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Derived

    /// Client-side validity gate. Web performs these same checks in
    /// zod before calling the server action (reimbursement-form.tsx
    /// schema); the RPC also rechecks server-side via RAISE EXCEPTION.
    public var canSubmit: Bool {
        guard !itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard amountYuan > 0 else { return false }
        return !isSubmitting
    }

    // MARK: - Submit

    @discardableResult
    public func submit() async -> Bool {
        let trimmedItem = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedItem.isEmpty else {
            errorMessage = "请填写报销项目"
            return false
        }
        guard !trimmedMerchant.isEmpty else {
            errorMessage = "请填写商户/收款方"
            return false
        }
        guard !trimmedPurpose.isEmpty else {
            errorMessage = "请填写用途说明"
            return false
        }
        guard amountYuan > 0 else {
            errorMessage = "金额必须大于 0"
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        // Yuan → cents. NSDecimalNumber keeps the arithmetic exact
        // (avoids 19.99 → 1998).
        let cents = NSDecimalNumber(decimal: amountYuan)
            .multiplying(by: 100)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))
        let amountCents = cents.intValue

        let trimmedBusinessReason = businessReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelated = relatedProject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines)

        let input = ReimbursementSubmitInput(
            itemDescription: trimmedItem,
            category: category,
            purchaseDate: Self.yyyyMMdd.string(from: purchaseDate),
            amountCents: amountCents,
            currency: trimmedCurrency.isEmpty ? nil : trimmedCurrency,
            merchant: trimmedMerchant,
            paymentMethod: paymentMethod,
            purpose: trimmedPurpose,
            priority: priority,
            businessReason: trimmedBusinessReason.isEmpty ? nil : trimmedBusinessReason,
            relatedProject: trimmedRelated.isEmpty ? nil : trimmedRelated,
            attachments: attachments,
            receiptUrls: receiptUrls
        )

        do {
            let id: UUID = try await client
                .rpc("approvals_submit_reimbursement", params: input)
                .execute()
                .value
            self.createdRequestId = id
            return true
        } catch {
            self.errorMessage = prettyApprovalRPCError(error)
            return false
        }
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
