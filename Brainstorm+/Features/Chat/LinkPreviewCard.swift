import SwiftUI
import Combine
import Supabase
import Auth
import SafariServices

/// Iter 7 Phase 1.2 — render a small og:* preview card for the first URL
/// in a message. Async fetches via `LinkPreviewService` (POSTs to
/// `/api/scrape`); cached in NSCache shared via environment.
///
/// Tap → opens URL in SFSafariViewController.
struct LinkPreviewCard: View {
    let url: URL
    @ObservedObject var fetcher: LinkPreviewFetcher
    @State private var showSafari = false

    var body: some View {
        Button {
            Haptic.light()
            showSafari = true
        } label: {
            HStack(spacing: BsSpacing.sm + 2) {
                if let img = fetcher.preview?.imageURL {
                    AsyncImage(url: img) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ZStack {
                                BsColor.surfaceTertiary
                                Image(systemName: "link")
                                    .foregroundStyle(BsColor.inkMuted)
                            }
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous))
                } else {
                    ZStack {
                        BsColor.brandAzure.opacity(0.15)
                        Image(systemName: "link")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(BsColor.brandAzure)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(fetcher.preview?.title ?? url.host ?? url.absoluteString)
                        .font(BsTypography.bodySmall.weight(.semibold))
                        .foregroundStyle(BsColor.ink)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    if let desc = fetcher.preview?.description, !desc.isEmpty {
                        Text(desc)
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(fetcher.preview?.siteName ?? url.host ?? "")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(BsSpacing.sm + 2)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .fill(BsColor.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .task {
            await fetcher.fetchIfNeeded(url: url)
        }
        .sheet(isPresented: $showSafari) {
            SafariView(url: url)
        }
    }
}

/// 包一层 SFSafariViewController,UIViewControllerRepresentable 跟全 app
/// 其它 Safari 入口同模式。
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// Per-bubble fetcher — owns its own NSCache key + state. Created per
/// preview card; shares the NSCache so repeated URLs across messages reuse.
@MainActor
final class LinkPreviewFetcher: ObservableObject {
    @Published var preview: ChatLinkPreview?
    @Published var isLoading = false
    private static let cache: NSCache<NSURL, NSDictionary> = {
        let c = NSCache<NSURL, NSDictionary>()
        c.countLimit = 100
        return c
    }()

    func fetchIfNeeded(url: URL) async {
        if preview != nil { return }
        if let cached = Self.cache.object(forKey: url as NSURL) {
            preview = ChatLinkPreview(
                url: url,
                title: cached["title"] as? String,
                description: cached["description"] as? String,
                imageURL: (cached["thumbnail"] as? String).flatMap { URL(string: $0) },
                siteName: cached["siteName"] as? String
            )
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await LinkPreviewService.shared.scrape(url: url)
            preview = result
            // Cache as plain NSDictionary for cross-instance reuse.
            let dict: NSDictionary = [
                "title": result.title ?? "",
                "description": result.description ?? "",
                "thumbnail": result.imageURL?.absoluteString ?? "",
                "siteName": result.siteName ?? ""
            ]
            Self.cache.setObject(dict, forKey: url as NSURL)
        } catch {
            // Silent — cards degrade to "URL host" view.
        }
    }
}

/// Service hitting `/api/scrape`. Reuses Supabase auth header.
final class LinkPreviewService {
    static let shared = LinkPreviewService()
    private init() {}

    func scrape(url: URL) async throws -> ChatLinkPreview {
        // 使用 AppEnvironment.webAPIBaseURL —— 跟 AI 分析、approvals 等模块
        // 同一个 Vercel 域 (zyoffice.me)。
        let endpoint = AppEnvironment.webAPIBaseURL.appendingPathComponent("/api/scrape")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 注入 Supabase access token 作为 cookie 兜底失败时的备用 auth (web 用
        // server-side cookie auth)。Bearer 现在 web /api/scrape 的 createClient
        // 会查 cookie,iOS 没 cookie 会返回 401 —— 这是预期降级。下个 sprint 会
        // 把 /api/scrape 改成接受 Bearer Apns token。
        if let token = try? await supabase.auth.session.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload = ["url": url.absoluteString]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let title = json["title"] as? String
        let desc = json["description"] as? String
        let thumb = (json["thumbnail"] as? String).flatMap { URL(string: $0) }
        let site = json["siteName"] as? String

        return ChatLinkPreview(
            url: url,
            title: title,
            description: desc,
            imageURL: thumb,
            siteName: site
        )
    }
}

// MARK: - URL detection helpers

extension String {
    /// Returns the first URL substring detected by NSDataDetector. Fast,
    /// uses Apple's built-in tokenizer; ignores non-http schemes for safety.
    func firstDetectedURL() -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(startIndex..., in: self)
        guard let match = detector.firstMatch(in: self, options: [], range: range),
              let url = match.url else { return nil }
        // Filter to http(s) only — emails / tel: / etc. are also tagged as
        // links by NSDataDetector but we don't want previews for those.
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }
}
