import Foundation
import Supabase

// ══════════════════════════════════════════════════
// AIAnalysisService
// 1. Reads active AI provider metadata from `api_keys` (providerId, model,
//    provider_name only — encrypted api_key stays server-side).
// 2. Streams `/api/ai/analyze` SSE from Web (Next.js route decrypts the key
//    on the server). Parses `data: {...}` events line-by-line using
//    `URLSession.bytes(for:).lines` — the same pattern used by
//    `AICopilotService`.
// ══════════════════════════════════════════════════

public enum AIAnalysisEvent {
    case progress(AIAnalysisProgress)
    case scrapedData([String: Any])
    case aiToken(String)
    case aiDone(String)
    case serverError(String)
}

public enum AIAnalysisServiceError: Swift.Error, LocalizedError {
    case noProvider
    case unauthorized
    case invalidResponse
    case server(String)
    case streamDropped

    public var errorDescription: String? {
        switch self {
        case .noProvider: return "未配置可用的 AI 供应商，请联系管理员。"
        case .unauthorized: return "登录已过期，请重新登录。"
        case .invalidResponse: return "响应异常"
        case .server(let msg): return msg
        case .streamDropped: return "分析流意外中断（可能超时或网络问题），请重试"
        }
    }
}

public final class AIAnalysisService {
    private let client: SupabaseClient
    private let analyzeURL: URL

    public init(client: SupabaseClient = supabase) {
        self.client = client
        self.analyzeURL = AppEnvironment.webAPIBaseURL.appendingPathComponent("api/ai/analyze")
    }

    // MARK: - Provider lookup

    /// Mirror of Web `getActiveAIConfig()` — but iOS only sees metadata.
    /// Encrypted `api_key` is deliberately excluded; the Web analyze route
    /// decrypts it server-side. RLS policy `authenticated_read_active_keys`
    /// in migration 007 already permits this read.
    public func loadActiveProvider() async throws -> AIAnalysisProvider {
        struct APIKeyRow: Decodable {
            let id: String
            let providerName: String
            let defaultModel: String?

            enum CodingKeys: String, CodingKey {
                case id
                case providerName = "provider_name"
                case defaultModel = "default_model"
            }
        }

        // Client-side filter for non-null default_model. Supabase-swift's
        // `.not("col", operator: .is, value: "null")` signature is brittle
        // across package versions, so we pull the small number of active
        // providers (usually 1–2) and filter in-memory.
        let rows: [APIKeyRow] = try await client
            .from("api_keys")
            .select("id, provider_name, default_model")
            .eq("is_active", value: true)
            .order("created_at", ascending: true)
            .limit(5)
            .execute()
            .value

        guard let row = rows.first(where: { ($0.defaultModel ?? "").isEmpty == false }),
              let model = row.defaultModel else {
            throw AIAnalysisServiceError.noProvider
        }

        return AIAnalysisProvider(
            providerId: row.id,
            providerName: row.providerName,
            model: model
        )
    }

    // MARK: - SSE streaming

    /// Opens the SSE pipe and yields typed events as the server emits them.
    /// Throws `AIAnalysisServiceError.streamDropped` if the socket closes
    /// without a terminal `ai_done` / `error` event (Vercel timeout etc.).
    public func streamAnalysis(
        url: String,
        platform: MediaPlatform,
        provider: AIAnalysisProvider,
        images: [String]
    ) -> AsyncThrowingStream<AIAnalysisEvent, Swift.Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [analyzeURL] in
                do {
                    let session = try await supabase.auth.session
                    let token = session.accessToken

                    var request = URLRequest(url: analyzeURL)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    struct Payload: Encodable {
                        let url: String
                        let platform: String
                        let providerId: String
                        let model: String
                        let images: [String]
                    }

                    let payload = Payload(
                        url: url,
                        platform: platform.rawValue,
                        providerId: provider.providerId,
                        model: provider.model,
                        images: images
                    )
                    request.httpBody = try JSONEncoder().encode(payload)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw AIAnalysisServiceError.invalidResponse
                    }

                    if http.statusCode == 401 { throw AIAnalysisServiceError.unauthorized }

                    if http.statusCode != 200 {
                        // Error payloads are JSON, not SSE
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let msg = Self.decodeErrorBody(data) ?? "请求失败 (HTTP \(http.statusCode))"
                        throw AIAnalysisServiceError.server(msg)
                    }

                    var receivedTerminal = false

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        guard !jsonStr.isEmpty else { continue }
                        guard let data = jsonStr.data(using: .utf8) else { continue }
                        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        guard let type = raw["type"] as? String else { continue }

                        switch type {
                        case "progress":
                            let phaseRaw = raw["phase"] as? String ?? "INIT"
                            let phase = AIAnalysisPhase(rawValue: phaseRaw) ?? .initPhase
                            let message = raw["message"] as? String ?? ""
                            let percent = (raw["progress"] as? Int) ?? Int((raw["progress"] as? Double) ?? 0)
                            continuation.yield(.progress(AIAnalysisProgress(phase: phase, message: message, percent: percent)))
                        case "scraped_data":
                            if let payload = raw["data"] as? [String: Any] {
                                continuation.yield(.scrapedData(payload))
                            }
                        case "ai_token":
                            if let content = raw["content"] as? String, !content.isEmpty {
                                continuation.yield(.aiToken(content))
                            }
                        case "ai_done":
                            receivedTerminal = true
                            let report = (raw["report"] as? String) ?? ""
                            continuation.yield(.aiDone(report))
                        case "error":
                            receivedTerminal = true
                            let msg = (raw["message"] as? String) ?? "分析失败"
                            continuation.yield(.serverError(msg))
                        default:
                            continue
                        }
                    }

                    if !receivedTerminal && !Task.isCancelled {
                        throw AIAnalysisServiceError.streamDropped
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func decodeErrorBody(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["error"] as? String
    }
}

// MARK: - Intel-report parsing

public enum MediaReportParseResult {
    case ok(MediaAnalysisResult)
    case failed(String)
}

public enum MediaAnalysisParser {
    /// Mirrors `tryParseMediaAnalysis` in page.tsx: strips markdown fences,
    /// falls back to extracting the outermost {...} substring, then
    /// JSON-decodes into `MediaAnalysisResult`.
    public static func parse(_ raw: String) -> MediaReportParseResult {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.lowercased().hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty { return .failed("内容为空") }

        if let data = cleaned.data(using: .utf8),
           let result = try? JSONDecoder().decode(MediaAnalysisResult.self, from: data) {
            return .ok(result)
        }

        // Fallback: extract first complete {...} block.
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"),
           end > start {
            let slice = String(cleaned[start...end])
            if let data = slice.data(using: .utf8),
               let result = try? JSONDecoder().decode(MediaAnalysisResult.self, from: data) {
                return .ok(result)
            }
        }

        return .failed("JSON 解析失败 — Schema 不匹配或格式错误")
    }
}
