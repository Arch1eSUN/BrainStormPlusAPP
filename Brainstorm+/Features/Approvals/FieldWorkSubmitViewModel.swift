import Foundation
import Combine
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Field-work submit ViewModel.
//
// Parity target: Web `submitFieldWorkRequest`
// (src/lib/actions/field-work.ts) + `src/components/approval/
// field-work-form.tsx`.
//
// Business rule: field-work requests must be submitted at least one
// day ahead of `target_date`. The RPC enforces this via
// `(p_target_date - CURRENT_DATE) >= 1` and raises "外勤申请必须至少
// 提前一天提交" on failure. The ViewModel also gates `canSubmit`
// client-side for a snappier UX, but the server is the source of
// truth.
// ══════════════════════════════════════════════════════════════════

@MainActor
public final class FieldWorkSubmitViewModel: ObservableObject {
    // MARK: - Form state

    @Published public var targetDate: Date = Calendar.current.date(
        byAdding: .day,
        value: 1,
        to: Date()
    ) ?? Date()
    @Published public var location: String = ""
    @Published public var reason: String = ""
    @Published public var expectedReturn: String = ""

    // MARK: - Submit state

    @Published public private(set) var isSubmitting: Bool = false
    @Published public var errorMessage: String?
    @Published public private(set) var createdRequestId: UUID?

    private let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Derived

    /// Matches the server's "at least 1 day ahead" rule. Uses UTC for
    /// the comparison anchor because the DB DATE column is tz-naive;
    /// device-local wall clock could otherwise let users submit a
    /// "tomorrow" that's already "today" in the server's zone.
    public var isTargetDateValid: Bool {
        let cal = Calendar(identifier: .iso8601)
        var utcCal = cal
        utcCal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let todayUTC = utcCal.startOfDay(for: Date())
        let targetUTC = utcCal.startOfDay(for: targetDate)
        guard let diff = utcCal.dateComponents([.day], from: todayUTC, to: targetUTC).day else {
            return false
        }
        return diff >= 1
    }

    public var canSubmit: Bool {
        guard !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard isTargetDateValid else { return false }
        return !isSubmitting
    }

    // MARK: - Submit

    @discardableResult
    public func submit() async -> Bool {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReturn = expectedReturn.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedLocation.isEmpty else {
            errorMessage = "请填写外勤地点"
            return false
        }
        guard !trimmedReason.isEmpty else {
            errorMessage = "请填写外勤事由"
            return false
        }
        guard isTargetDateValid else {
            errorMessage = "外勤申请必须至少提前一天提交"
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let input = FieldWorkSubmitInput(
            targetDate: Self.yyyyMMdd.string(from: targetDate),
            location: trimmedLocation,
            reason: trimmedReason,
            expectedReturn: trimmedReturn.isEmpty ? nil : trimmedReturn
        )

        do {
            let id: UUID = try await client
                .rpc("approvals_submit_field_work", params: input)
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
