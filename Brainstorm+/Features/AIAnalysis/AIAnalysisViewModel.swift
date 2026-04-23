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
    @Published public var report: String = ""
    @Published public var scrapedData: [String: Any]? = nil

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
        scrapedData = nil
        errorMessage = nil
    }

    // MARK: - Event handler

    private func apply(_ event: AIAnalysisEvent) {
        switch event {
        case .progress(let p):
            self.progress = p
            if !phaseHistory.contains(p.phase) {
                phaseHistory.append(p.phase)
            }
        case .scrapedData(let data):
            self.scrapedData = data
        case .aiToken(let token):
            self.report.append(token)
        case .aiDone(let finalReport):
            let trimmed = finalReport.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.report = trimmed
            } else {
                self.report = self.report.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            self.pageState = .done
        case .serverError(let msg):
            self.errorMessage = msg
            self.pageState = .error(msg)
        }
    }
}
