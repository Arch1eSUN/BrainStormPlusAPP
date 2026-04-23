import Foundation
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.x — Medical-cert upload helper for the leave submission
// form. Thin wrapper around the same `approval_attachments` bucket
// that reimbursement receipts land in — the bucket is mixed-type
// (image/* + application/pdf) and its INSERT RLS is keyed to the
// caller's auth.uid() as the first path segment, which both upload
// paths honour by prepending `{userId}/`.
//
// Why a separate file from ApprovalStorageClient.uploadReceipt:
//   - semantic clarity at call sites (reading a VM that calls
//     `.uploadMedicalCert(…)` is louder than `.uploadReceipt(…)` with
//     a comment explaining the reuse);
//   - room to evolve: if one day medical certs need encryption-at-rest
//     / a different retention policy / HIPAA-adjacent handling, this
//     helper is the one place that pivots. Today the bucket is shared
//     so we don't create a new one (RLS churn) — see memory note
//     `project_brainstorm_migration_drift`.
// ══════════════════════════════════════════════════════════════════

@MainActor
public enum LeaveStorageClient {
    /// Reuses the reimbursement bucket on purpose — a new bucket would
    /// require extending the 20260418100000_approval_attachments_rls
    /// policy set to match, and the policy is already permissive
    /// enough (first-folder = auth.uid()).
    public static let bucket = ApprovalStorageClient.bucket

    /// Upload a single medical-cert file and return its public URL.
    ///
    /// `data`     — raw bytes; PhotosPicker gives JPEG-decoded Data,
    ///              `.fileImporter` gives PDF/image bytes via
    ///              `Data(contentsOf:)`.
    /// `fileName` — only used to derive the extension on the stored
    ///              path. The original name is NOT persisted on the
    ///              object path (collisions avoided with UUID), but
    ///              callers typically stash it in a DB column so the
    ///              detail view can show the original name.
    /// `mimeType` — Content-Type on upload; mixed-type bucket.
    ///
    /// Path convention: `{userId}/medical_cert/{uuid}.{ext}`. The
    /// `medical_cert/` segment is informational only — RLS cares about
    /// the top-level auth.uid() folder, not sub-folders — but it makes
    /// the Storage console easier to skim when a cert needs to be
    /// reviewed out-of-band.
    public static func uploadMedicalCert(
        data: Data,
        fileName: String,
        mimeType: String,
        client: SupabaseClient = supabase
    ) async throws -> String {
        let userId = try await client.auth.session.user.id
        let ext = (fileName as NSString).pathExtension.lowercased()
        let uuid = UUID().uuidString
        let fileComponent = ext.isEmpty ? uuid : "\(uuid).\(ext)"
        let path = "\(userId.uuidString)/medical_cert/\(fileComponent)"

        _ = try await client.storage
            .from(bucket)
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: mimeType, upsert: true)
            )

        let publicURL = try client.storage
            .from(bucket)
            .getPublicURL(path: path)

        return publicURL.absoluteString
    }
}
