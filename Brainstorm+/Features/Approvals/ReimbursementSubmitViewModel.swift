import Foundation
import Combine
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
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
// Attachments / receipt URLs (Batch C.1): iOS now uploads to the
// `approval_attachments` bucket via `ApprovalStorageClient`, matching
// Web's `ReceiptUploader` (src/components/approval/forms/receipt-uploader.tsx).
// URLs are accumulated into `receiptUrls` and sent through the RPC's
// `p_receipt_urls` JSONB param on submit. The RPC stores them on
// `approval_request_reimbursement.receipt_urls`.
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
    // Top-level `attachments` stays empty — Web's reimbursement form
    // routes everything through `receipt_urls` and leaves the parent
    // `approval_requests.attachments` untouched. Keeping this
    // published in case a future polish pass reintroduces the
    // distinction.
    @Published public var attachments: [ApprovalAttachment] = []
    @Published public var receiptUrls: [String] = []

    // MARK: - Submit state

    @Published public private(set) var isSubmitting: Bool = false
    @Published public private(set) var isUploading: Bool = false
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
        return !isSubmitting && !isUploading
    }

    // MARK: - Receipt upload ingestion

    /// PhotosPicker ingestion. Each selected item is streamed into the
    /// `approval_attachments` bucket via `ApprovalStorageClient` and
    /// the returned public URL is appended to `receiptUrls`. Errors
    /// are accumulated on `errorMessage` but don't short-circuit the
    /// remaining items — matches Web's `receipt-uploader.tsx:42-47`
    /// "continue on failure" behavior.
    public func ingestPhotoItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                continue
            }
            // PhotosPicker hands back HEIC-decoded JPEG by default.
            let fileName = "IMG_\(UUID().uuidString.prefix(8)).jpg"
            await uploadOne(data: data, fileName: fileName, mimeType: "image/jpeg")
        }
    }

    /// `.fileImporter` result ingestion. Walks security-scoped URLs,
    /// decodes MIME type from the extension, uploads sequentially.
    public func ingestPickedFiles(_ result: Result<[URL], Error>) async {
        let urls: [URL]
        switch result {
        case .success(let picked):
            urls = picked
        case .failure(let error):
            errorMessage = "选择文件失败: \(ErrorLocalizer.localize(error))"
            return
        }
        guard !urls.isEmpty else { return }

        isUploading = true
        defer { isUploading = false }

        for url in urls {
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else { continue }
            let fileName = url.lastPathComponent
            let mime = UTType(filenameExtension: url.pathExtension)?
                .preferredMIMEType ?? "application/octet-stream"
            await uploadOne(data: data, fileName: fileName, mimeType: mime)
        }
    }

    public func removeReceipt(at index: Int) {
        guard receiptUrls.indices.contains(index) else { return }
        receiptUrls.remove(at: index)
    }

    private func uploadOne(data: Data, fileName: String, mimeType: String) async {
        do {
            let publicUrl = try await ApprovalStorageClient.uploadReceipt(
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                client: client
            )
            receiptUrls.append(publicUrl)
        } catch {
            errorMessage = "上传失败: \(ErrorLocalizer.localize(error))"
        }
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
