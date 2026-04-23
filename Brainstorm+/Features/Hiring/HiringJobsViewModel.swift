import Foundation
import Combine

@MainActor
public final class HiringJobsViewModel: ObservableObject {
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
            positions = try await repo.fetchJobPositions(search: term.isEmpty ? nil : term)
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
        }
    }

    public func delete(_ position: JobPosition) async {
        let prev = positions
        positions.removeAll { $0.id == position.id }
        do {
            try await repo.deleteJobPosition(id: position.id)
        } catch {
            positions = prev
            errorMessage = "删除失败：\(ErrorLocalizer.localize(error))"
        }
    }
}
