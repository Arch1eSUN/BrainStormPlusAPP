import Foundation
import Supabase

// ══════════════════════════════════════════════════════════════════
// Batch C.4c — Minimal storage helper for the knowledge-base
// file-attachment flow. Sibling of `ApprovalStorageClient` from
// Batch C.1; lives in its own file because the bucket + RLS policy
// are distinct from the approval-attachments bucket.
//
// Bucket + path contract — see migration
// `BrainStorm+-Web/supabase/migrations/039_knowledge_storage_bucket.sql`:
//   - bucket: `knowledge-files` (public, 100 MB cap, admin-only writes)
//   - RLS INSERT requires `storage.foldername(name)[1] = auth.uid()`,
//     so the path has to lead with the caller's user id just like the
//     approval-attachments bucket.
//   - path:   `{auth.uid}/{uuid}.{ext}`
//
// Web's equivalent server path is
// `src/app/api/knowledge/upload/route.ts:110-130` which also wraps the
// upload in a background job that does PDF text extraction + inserts
// the `knowledge_articles` row. That pipeline is intentionally NOT
// ported to iOS — we upload the raw file and create the article in
// one VM call with no server-side parsing. See
// `KnowledgeListViewModel.uploadFile(...)` + the scope notes in the
// batch audit doc.
// ══════════════════════════════════════════════════════════════════

@MainActor
public enum KnowledgeStorageClient {
    /// Bucket id from migration 039. Public read, admin-gated write.
    public static let bucket = "knowledge-files"

    /// Upload a single file and return its public URL.
    ///
    /// `data`     — raw bytes (PhotosPicker's `loadTransferable(type: Data.self)`
    ///              or `Data(contentsOf:)` for a `.fileImporter` URL).
    /// `fileName` — used to derive the extension for the storage key.
    ///              The original filename is preserved at the caller as
    ///              the `knowledge_articles.title` default (matching
    ///              Web's `title: file.name`).
    /// `mimeType` — persisted on the row as `file_type`.
    ///
    /// Returns the public URL to store on
    /// `knowledge_articles.file_url`. Throws whatever the Supabase SDK
    /// throws on auth / upload failure; callers surface via the VM's
    /// `errorMessage` / `.zyErrorBanner`.
    public static func uploadFile(
        data: Data,
        fileName: String,
        mimeType: String,
        client: SupabaseClient = supabase
    ) async throws -> (publicURL: String, storagePath: String) {
        let userId = try await client.auth.session.user.id
        let ext = (fileName as NSString).pathExtension.lowercased()
        let uuid = UUID().uuidString
        let fileComponent = ext.isEmpty ? uuid : "\(uuid).\(ext)"
        let storagePath = "\(userId.uuidString)/\(fileComponent)"

        _ = try await client.storage
            .from(bucket)
            .upload(
                storagePath,
                data: data,
                options: FileOptions(contentType: mimeType, upsert: true)
            )

        let publicURL = try client.storage
            .from(bucket)
            .getPublicURL(path: storagePath)

        return (publicURL.absoluteString, storagePath)
    }
}
