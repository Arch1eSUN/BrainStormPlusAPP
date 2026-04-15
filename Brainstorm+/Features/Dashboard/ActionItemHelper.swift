import SwiftUI
import Supabase

public struct ActionItemHelper {
    @ViewBuilder
    public static func destination(for title: String) -> some View {
        switch title {
        case "Tasks":
            TaskListView(viewModel: TaskListViewModel(client: supabase))
        default:
            PlaceholderDestination(title: title)
        }
    }
}
