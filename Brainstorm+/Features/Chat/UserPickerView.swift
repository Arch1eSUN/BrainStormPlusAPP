import SwiftUI

/// Multi-select user picker for chat conversation creation.
///
/// Loads profiles (excluding self) via `ChatListViewModel.fetchUsers`, mirrors
/// Web's `UserSelector` behavior for the `createConversation` / `?dm=` flows:
/// name + display-name search, tap row to toggle selection. Debounced search
/// so every keystroke doesn't hit PostgREST.
public struct UserPickerView: View {
    @ObservedObject var viewModel: ChatListViewModel
    @Binding var selectedUserIds: Set<UUID>

    @State private var users: [Profile] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    public init(viewModel: ChatListViewModel, selectedUserIds: Binding<Set<UUID>>) {
        self.viewModel = viewModel
        self._selectedUserIds = selectedUserIds
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("搜索同事", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, BsSpacing.lg)
                .padding(.top, BsSpacing.sm)
                .onChange(of: searchText) { _, newValue in
                    scheduleSearch(query: newValue)
                }

            if isLoading && users.isEmpty {
                ProgressView().padding(.top, BsSpacing.xl)
                Spacer()
            } else if users.isEmpty {
                BsEmptyState(title: "未找到用户", systemImage: "person.slash")
                Spacer()
            } else {
                List(users) { user in
                    Button {
                        toggle(user.id)
                    } label: {
                        row(for: user)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }

            if let error = errorMessage {
                Text(error)
                    .font(BsTypography.caption)
                    .foregroundStyle(BsColor.danger)
                    .padding(BsSpacing.lg)
            }
        }
        .task {
            await load(query: nil)
        }
    }

    @ViewBuilder
    private func row(for user: Profile) -> some View {
        HStack(spacing: BsSpacing.md) {
            ZStack {
                Circle()
                    .fill(BsColor.brandAzure.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(initials(for: user))
                    .font(BsTypography.cardSubtitle)
                    .foregroundStyle(BsColor.brandAzure)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(displayName(for: user))
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: user))
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.ink)
                if let dept = user.department, !dept.isEmpty {
                    Text(dept)
                        .font(BsTypography.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
            Spacer()
            if selectedUserIds.contains(user.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BsColor.brandAzure)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(BsColor.inkMuted)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, BsSpacing.xs)
    }

    private func toggle(_ id: UUID) {
        if selectedUserIds.contains(id) {
            selectedUserIds.remove(id)
        } else {
            selectedUserIds.insert(id)
        }
    }

    private func displayName(for user: Profile) -> String {
        user.fullName ?? user.displayName ?? user.email ?? "未命名用户"
    }

    private func initials(for user: Profile) -> String {
        let name = displayName(for: user)
        guard let first = name.first else { return "?" }
        return String(first).uppercased()
    }

    /// Debounce keystrokes by ~300ms so each character doesn't spawn a network
    /// call. Cancels previous in-flight task before scheduling a new one.
    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await load(query: query)
        }
    }

    private func load(query: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await viewModel.fetchUsers(search: query)
            users = fetched
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
        }
    }
}
