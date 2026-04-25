import Foundation
import SwiftUI
import Combine

@MainActor
public final class AIAnalysisViewModel: ObservableObject {
    // Inputs
    @Published public var platform: MediaPlatform = .douyin
    @Published public var inputUrl: String = ""
    @Published public var imageUrlsText: String = ""

    // Page / stream state
    @Published public var pageState: AIAnalysisPageState = .idle
    @Published public var progress: AIAnalysisProgress? = nil
    @Published public var phaseHistory: [AIAnalysisPhase] = []
    /// Per-phase timing log (used by the expandable detail panel).
    @Published public var stageLogs: [AIAnalysisStageLog] = []
    /// Wall-clock start of the current run; `nil` when idle.
    @Published public var runStartedAt: Date? = nil
    /// Total duration once `pageState == .done`.
    @Published public var totalDurationSeconds: Double? = nil
    @Published public var report: String = ""
    @Published public var scrapedData: [String: Any]? = nil

    /// Streaming `<think>` stripper state — defense in depth in case the
    /// server forwards a leak (different provider, future regression, etc.).
    private var clientStrip = ClientThinkStripState()

    // Provider
    @Published public var provider: AIAnalysisProvider? = nil
    @Published public var providerLoadError: String? = nil

    // Error banner shared with .zyErrorBanner($vm.errorMessage)
    @Published public var errorMessage: String? = nil

    private let service: AIAnalysisService
    private var streamTask: Task<Void, Never>? = nil

    public init(service: AIAnalysisService = AIAnalysisService()) {
        self.service = service
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: - Provider load

    public func loadProvider() async {
        do {
            let p = try await service.loadActiveProvider()
            self.provider = p
            self.providerLoadError = nil
        } catch let err as AIAnalysisServiceError {
            self.provider = nil
            self.providerLoadError = err.errorDescription
        } catch {
            self.provider = nil
            self.providerLoadError = ErrorLocalizer.localize(error)
        }
    }

    // MARK: - Parse helpers

    public var parsedImageUrls: [String] {
        imageUrlsText
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && ($0.hasPrefix("http://") || $0.hasPrefix("https://")) }
    }

    public var canSubmit: Bool {
        !inputUrl.trimmingCharacters(in: .whitespaces).isEmpty && provider != nil && pageState != .streaming
    }

    // MARK: - Submit

    public func submit() {
        let url = inputUrl.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else {
            errorMessage = "请提供媒体链接"
            pageState = .error("请提供媒体链接")
            return
        }
        guard let provider = provider else {
            let msg = providerLoadError ?? "未配置 AI 供应商，请联系管理员在设置中添加。"
            errorMessage = msg
            pageState = .error(msg)
            return
        }

        // Reset
        streamTask?.cancel()
        pageState = .streaming
        errorMessage = nil
        report = ""
        scrapedData = nil
        phaseHistory = []
        stageLogs = []
        totalDurationSeconds = nil
        runStartedAt = Date()
        clientStrip = ClientThinkStripState()
        progress = AIAnalysisProgress(phase: .initPhase, message: "准备中...", percent: 0)

        let images = parsedImageUrls

        streamTask = Task { [service, weak self] in
            let stream = service.streamAnalysis(
                url: url,
                platform: self?.platform ?? .douyin,
                provider: provider,
                images: images
            )
            do {
                for try await event in stream {
                    guard let self else { return }
                    self.apply(event)
                }
                // Stream finished cleanly — any terminal state already applied.
            } catch let err as AIAnalysisServiceError {
                await MainActor.run {
                    self?.errorMessage = err.errorDescription
                    self?.pageState = .error(err.errorDescription ?? "分析失败")
                }
            } catch is CancellationError {
                // user-initiated stop; keep whatever we have
            } catch {
                await MainActor.run {
                    self?.errorMessage = ErrorLocalizer.localize(error)
                    self?.pageState = .error(ErrorLocalizer.localize(error))
                }
            }
        }
    }

    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        if pageState == .streaming {
            pageState = .done
        }
    }

    public func reset() {
        streamTask?.cancel()
        streamTask = nil
        pageState = .idle
        report = ""
        progress = nil
        phaseHistory = []
        stageLogs = []
        runStartedAt = nil
        totalDurationSeconds = nil
        scrapedData = nil
        errorMessage = nil
        clientStrip = ClientThinkStripState()
    }

    // MARK: - Event handler

    private func apply(_ event: AIAnalysisEvent) {
        switch event {
        case .progress(let p):
            // Mark previous active stage complete (closes its row in the log).
            if let last = stageLogs.indices.last, stageLogs[last].completedAt == nil {
                stageLogs[last].completedAt = Date()
            }
            self.progress = p
            if !phaseHistory.contains(p.phase) {
                phaseHistory.append(p.phase)
            }
            if p.phase != .done {
                stageLogs.append(
                    AIAnalysisStageLog(phase: p.phase, message: p.message, timestamp: Date(), completedAt: nil)
                )
            }
        case .scrapedData(let data):
            self.scrapedData = data
        case .aiToken(let token):
            // Defense-in-depth: even if the server already strips, run the
            // streaming-safe stripper here so a future provider regression
            // can never leak <think> into the visible report.
            let safe = stripThinkStreaming(state: &clientStrip, token: token)
            if !safe.isEmpty {
                self.report.append(safe)
            }
        case .aiDone(let finalReport):
            // Final whole-document sweep + flush.
            var combined = finalReport
            if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                combined = self.report
            }
            combined.append(flushThinkStreaming(state: &clientStrip))
            let cleaned = sanitizeFinalReport(combined).trimmingCharacters(in: .whitespacesAndNewlines)
            self.report = cleaned

            // Close out any still-active stage entry.
            if let last = stageLogs.indices.last, stageLogs[last].completedAt == nil {
                stageLogs[last].completedAt = Date()
            }
            if let runStartedAt {
                self.totalDurationSeconds = Date().timeIntervalSince(runStartedAt)
            }
            self.pageState = .done
        case .serverError(let msg):
            self.errorMessage = msg
            self.pageState = .error(msg)
            if let last = stageLogs.indices.last, stageLogs[last].completedAt == nil {
                stageLogs[last].completedAt = Date()
            }
        }
    }
}

// MARK: - Client-side <think> stripper

/// Mirrors `BrainStorm+-Web/src/app/api/ai/analyze/route.ts` stripper.
struct ClientThinkStripState {
    var insideThink: Bool = false
    var pending: String = ""
}

private let kThinkOpen = try! NSRegularExpression(pattern: "<think(?:ing)?\\s*>", options: .caseInsensitive)
private let kThinkClose = try! NSRegularExpression(pattern: "</think(?:ing)?\\s*>", options: .caseInsensitive)

@MainActor
func stripThinkStreaming(state: inout ClientThinkStripState, token: String) -> String {
    var buf = state.pending + token
    var out = ""

    while !buf.isEmpty {
        if state.insideThink {
            let range = NSRange(buf.startIndex..., in: buf)
            if let m = kThinkClose.firstMatch(in: buf, options: [], range: range),
               let r = Range(m.range, in: buf) {
                buf = String(buf[r.upperBound...])
                state.insideThink = false
                continue
            }
            // Whole buffer still inside <think>; hold a small tail in case
            // </think> straddles the next chunk.
            if buf.count > 12 {
                state.pending = String(buf.suffix(12))
            } else {
                state.pending = buf
            }
            return out
        }

        let range = NSRange(buf.startIndex..., in: buf)
        if let m = kThinkOpen.firstMatch(in: buf, options: [], range: range),
           let r = Range(m.range, in: buf) {
            out += String(buf[..<r.lowerBound])
            buf = String(buf[r.upperBound...])
            state.insideThink = true
            continue
        }

        // No tag in buffer; hold trailing chars in case a partial "<thi"
        // straddles into the next chunk.
        if let lt = buf.lastIndex(of: "<") {
            let suffixCount = buf.distance(from: lt, to: buf.endIndex)
            if suffixCount <= 9 {
                out += String(buf[..<lt])
                state.pending = String(buf[lt...])
                return out
            }
        }
        out += buf
        state.pending = ""
        buf = ""
    }
    return out
}

@MainActor
func flushThinkStreaming(state: inout ClientThinkStripState) -> String {
    if state.insideThink {
        state.pending = ""
        return ""
    }
    let tail = state.pending
    state.pending = ""
    return tail
}

/// Whole-document final sweep — handles unclosed `<think>` openers.
@MainActor
func sanitizeFinalReport(_ raw: String) -> String {
    if raw.isEmpty { return raw }
    var s = raw

    // Drop any properly-bracketed <think>…</think> blocks.
    let bracketed = try! NSRegularExpression(
        pattern: "<think(?:ing)?\\s*>[\\s\\S]*?</think(?:ing)?\\s*>",
        options: [.caseInsensitive]
    )
    s = bracketed.stringByReplacingMatches(
        in: s, options: [],
        range: NSRange(s.startIndex..., in: s),
        withTemplate: ""
    )

    // Unclosed opener: drop everything from `<think…>` up to the first `{` / `[`.
    if let openMatch = kThinkOpen.firstMatch(
        in: s, options: [], range: NSRange(s.startIndex..., in: s)
    ),
       let openRange = Range(openMatch.range, in: s) {
        let prefix = String(s[..<openRange.lowerBound])
        let after = String(s[openRange.lowerBound...])
        if let jsonStart = after.firstIndex(where: { $0 == "{" || $0 == "[" }) {
            s = prefix + String(after[jsonStart...])
        } else {
            s = prefix
        }
    }

    // Catch dangling closer with no opener.
    s = kThinkClose.stringByReplacingMatches(
        in: s, options: [],
        range: NSRange(s.startIndex..., in: s),
        withTemplate: ""
    )

    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}
