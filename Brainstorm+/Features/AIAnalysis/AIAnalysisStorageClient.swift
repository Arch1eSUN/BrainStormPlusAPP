import Foundation
import Supabase

// ══════════════════════════════════════════════════════════════════
// AIAnalysisStorageClient — Iter 6 §A.9 (媒体分析截图 fallback)
//
// User snaps a screenshot of the share post (XHS feed, Douyin player, …)
// when the URL scraper hits anti-bot. We upload to the public `chat-files`
// bucket and pass the public URL into `imageUrls[]` of the analyze SSE
// payload — the AI vision model can then fetch + read it.
//
// Bucket choice: we reuse `chat-files` (migration 028) instead of standing
// up a fresh bucket because:
//   1. It's already public-read (AI vision models need a fetchable URL).
//   2. RLS INSERT enforces `storage.foldername(name)[1] = auth.uid()`,
//      same pattern as the rest of the app — no migration needed.
//   3. Path layout `{user_id}/ai-analysis/{uuid}.{ext}` keeps screenshots
//      out of chat-channel subdirectories so admins can audit/clean later.
// ══════════════════════════════════════════════════════════════════

@MainActor
public enum AIAnalysisStorageClient {
    /// Public chat bucket — see migration 028.
    public static let bucket = "chat-files"

    /// Upload a screenshot for AI vision analysis. Returns the public URL.
    ///
    /// - Parameters:
    ///   - data: PNG/JPEG bytes from `PhotosPicker`'s `loadTransferable(type: Data.self)`.
    ///   - mimeType: defaults to `image/jpeg` — PhotosPicker delivers HEIC/JPEG
    ///     bytes; storing as `image/jpeg` avoids the (rare) HEIC fetch issue
    ///     that some AI vision models still trip on.
    public static func uploadScreenshot(
        data: Data,
        mimeType: String = "image/jpeg",
        client: SupabaseClient = supabase
    ) async throws -> (publicURL: String, storagePath: String) {
        let userId = try await client.auth.session.user.id
        let ext: String
        switch mimeType {
        case "image/png": ext = "png"
        case "image/heic": ext = "heic"
        case "image/webp": ext = "webp"
        default: ext = "jpg"
        }
        let storagePath = "\(userId.uuidString)/ai-analysis/\(UUID().uuidString).\(ext)"

        _ = try await client.storage
            .from(bucket)
            .upload(
                storagePath,
                data: data,
                options: FileOptions(contentType: mimeType, upsert: false)
            )

        let publicURL = try client.storage
            .from(bucket)
            .getPublicURL(path: storagePath)

        return (publicURL.absoluteString, storagePath)
    }
}
