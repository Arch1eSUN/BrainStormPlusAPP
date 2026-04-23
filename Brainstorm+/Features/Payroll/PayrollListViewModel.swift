import Foundation
import Combine
import Supabase

@MainActor
public class PayrollListViewModel: ObservableObject {
    @Published public var payrolls: [PayrollRecord] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let client: SupabaseClient
    
    public init(client: SupabaseClient) {
        self.client = client
    }
    
    public func fetchPayrolls() async {
        isLoading = true
        errorMessage = nil
        do {
            self.payrolls = try await client
                .from("payroll_records")
                .select()
                .order("period", ascending: false)
                .execute()
                .value
        } catch {
            self.errorMessage = ErrorLocalizer.localize(error)
        }
        isLoading = false
    }
}
