import Foundation
import Combine

@MainActor
public final class HiringCandidatesViewModel: ObservableObject {
    @Published public private(set) var candidates: [Candidate] = []
    @Published public private(set) var positions: [JobPosition] = []
    @Published public var searchText: String = ""
    @Published public private(set) var isLoading: Bool = false
    @Published public var errorMessage: String?

    private let repo = HiringRepository.shared

    public init() {}

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            async let candidatesTask = repo.fetchCandidates(search: term.isEmpty ? nil : term)
            async let positionsTask = repo.fetchJobPositions(search: nil)
            candidates = try await candidatesTask
            positions = try await positionsTask
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
        }
    }

    public func delete(_ candidate: Candidate) async {
        let prev = candidates
        candidates.removeAll { $0.id == candidate.id }
        do {
            try await repo.deleteCandidate(id: candidate.id)
        } catch {
            candidates = prev
            errorMessage = "删除失败：\(ErrorLocalizer.localize(error))"
        }
    }
}
