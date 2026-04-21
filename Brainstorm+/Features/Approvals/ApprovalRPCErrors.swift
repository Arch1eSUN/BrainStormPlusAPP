import Foundation

/// Shared error-shaping helper for all approval SECURITY DEFINER RPCs.
///
/// PostgREST wraps `RAISE EXCEPTION '<message>'` (the form the Web
/// server actions and our RPCs use to surface validation failures) in
/// an error payload whose `localizedDescription` carries the raw
/// message behind an `ERROR:` prefix plus some framing. The UX goal
/// is that the user sees exactly the Chinese string the Postgres
/// function wrote — e.g. "调休额度不足：4 月剩余 2 天，本次申请该月
/// 3 天。每月 1 号自动刷新为 4 天。" — without the `ERROR: … (SQLSTATE …)`
/// noise bracketing it.
///
/// Consumers: all 4 Sprint 4.4 submit ViewModels + (in the future)
/// `ApprovalDetailViewModel.submitRevokeCompTime` which currently
/// carries a private near-duplicate of this logic. Not refactoring
/// that call site in 4.4 to keep the change surface small — a polish
/// pass can unify after the forms ship.
internal func prettyApprovalRPCError(_ error: Error) -> String {
    let raw = error.localizedDescription
    if let range = raw.range(of: "ERROR:") {
        return String(raw[range.upperBound...])
            .trimmingCharacters(in: .whitespaces)
    }
    return raw
}
