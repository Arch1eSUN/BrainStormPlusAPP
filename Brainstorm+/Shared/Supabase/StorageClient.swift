import Foundation
import Supabase

// ══════════════════════════════════════════════════════════════════
// Batch C.1 — Minimal Storage helper for the approval-attachments
// upload path. Mirrors Web's `ReceiptUploader`
// (src/components/approval/forms/receipt-uploader.tsx:38-54):
//
//   - bucket: `approval_attachments` (see migration
//     20260418100000_approval_attachments_rls.sql)
//   - path:   `{auth.uid}/{uuid}.{ext}` — the bucket's RLS INSERT
//             policy requires the first folder to match `auth.uid()`,
//             so the caller's user id is injected here rather than
//             leaked into the view layer.
//   - return: public URL (`getPublicURL` → absolute string), matching
//             Web's `getPublicUrl(filePath).publicUrl` output that gets
//             persisted as the `receipt_urls: string[]` column.
//
// Keep this file small and bucket-agnostic; future call sites (e.g.
// knowledge / chat) already have their own upload paths inline
// (ChatRoomViewModel.uploadAttachment) — no attempt to unify here,
// matching the iOS conventions file in the brief.
// ══════════════════════════════════════════════════════════════════

@MainActor
public enum ApprovalStorageClient {
    /// Bucket name mirrors Web's client-side upload at
    /// `receipt-uploader.tsx:38` (`supabase.storage.from('approval_attachments')`).
    public static let bucket = "approval_attachments"

    /// Upload a single file and return its public URL.
    ///
    /// `data`     — raw bytes (PhotosPicker's `loadTransferable(type: Data.self)`
    ///              or `Data(contentsOf:)` for `.fileImporter` URLs).
    /// `fileName` — used only to derive the extension; the stored path
    ///              is `{userId}/{uuid}.{ext}` to avoid collisions and
    ///              satisfy the RLS INSERT policy.
    /// `mimeType` — Content-Type header on the upload; the bucket is
    ///              mixed-type (image/* + application/pdf on Web).
    ///
    /// Throws whatever the Supabase SDK throws on auth / upload
    /// failure. Caller is expected to surface the localized
    /// description via the ViewModel's `errorMessage`.
    public static func uploadReceipt(
        data: Data,
        fileName: String,
        mimeType: String,
        client: SupabaseClient = supabase
    ) async throws -> String {
        let userId = try await client.auth.session.user.id
        let ext = (fileName as NSString).pathExtension.lowercased()
        let uuid = UUID().uuidString
        let fileComponent = ext.isEmpty ? uuid : "\(uuid).\(ext)"
        let path = "\(userId.uuidString)/\(fileComponent)"

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
