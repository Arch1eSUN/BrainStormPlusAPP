import Foundation
import Combine
import Supabase

@MainActor
public final class HiringCandidateDetailViewModel: ObservableObject {
    @Published public private(set) var candidate: Candidate?
    @Published public private(set) var positions: [JobPosition] = []
    @Published public private(set) var aiReview: CandidateAIReview?
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var toastMessage: String?

    /// 触发状态切到 `.offer` 时，View 侧读这个 flag 弹 confirmationDialog。
    @Published public var pendingOfferConfirmation: Bool = false

    public let candidateId: UUID

    private let repo = HiringRepository.shared

    public init(candidateId: UUID) {
        self.candidateId = candidateId
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let candidatesTask = repo.fetchCandidates(search: nil)
            async let positionsTask = repo.fetchJobPositions(search: nil)
            let all = try await candidatesTask
            positions = try await positionsTask
            candidate = all.first(where: { $0.id == candidateId })
            aiReview = parseReview(candidate?.aiSummary)
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
        }
    }

    public func transition(to status: Candidate.CandidateStatus) async {
        guard let candidate else { return }
        let prev = candidate
        self.candidate?.status = status
        do {
            try await repo.updateCandidateStatus(id: candidate.id, status: status)
            // TODO(hiring-offer-email-bridge): 已接入 /api/mobile/hiring/offer-email
            // 状态成功切到 .offer 后弹 confirmationDialog（View 侧），用户选择
            // "发送" 时再调用 `sendOfferEmail()`。503 / 失败时文案写入
            // errorMessage 但状态更新本身不回滚。
            if status == .offer {
                pendingOfferConfirmation = true
            }
        } catch {
            self.candidate = prev
            errorMessage = "状态更新失败：\(ErrorLocalizer.localize(error))"
        }
    }

    /// 调用 Web 路由发送 offer 邮件。503 / 其他失败时降级：保留状态，
    /// 只在 `errorMessage` 里写固定文案。
    public func sendOfferEmail() async {
        guard let candidate else { return }
        do {
            let session = try await supabase.auth.session
            let token = session.accessToken
            let url = AppEnvironment.webAPIBaseURL
                .appendingPathComponent("api/mobile/hiring/offer-email")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 30

            let payload: [String: Any] = [
                "candidate_id": candidate.id.uuidString,
                "email_template": "default",
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Offer 邮件发送失败，请在 Web 后台操作"
                return
            }
            if http.statusCode == 503 || http.statusCode >= 400 {
                // 按任务约定：503 或任意失败都降级提示，状态保持 .offer。
                _ = data
                errorMessage = "Offer 邮件发送失败，请在 Web 后台操作"
                return
            }
            toastMessage = "Offer 邮件已发送"
        } catch {
            errorMessage = "Offer 邮件发送失败，请在 Web 后台操作"
        }
    }

    private func parseReview(_ raw: String?) -> CandidateAIReview? {
        guard let raw = raw, !raw.isEmpty, let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(CandidateAIReview.self, from: data)
    }
}
