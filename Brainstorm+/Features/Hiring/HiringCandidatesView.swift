import SwiftUI

public struct HiringCandidatesView: View {
    @StateObject private var viewModel = HiringCandidatesViewModel()
    @State private var showCreate: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            if viewModel.isLoading && viewModel.candidates.isEmpty {
                ProgressView().padding(.top, 40)
            } else if viewModel.candidates.isEmpty {
                ContentUnavailableView(
                    "暂无候选人",
                    systemImage: "person.crop.square.filled.and.at.rectangle",
                    description: Text("点击右上角「添加候选人」开始录入。")
                )
            } else {
                List {
                    ForEach(viewModel.candidates) { c in
                        NavigationLink {
                            HiringCandidateDetailView(candidateId: c.id) {
                                Task { await viewModel.load() }
                            }
                        } label: {
                            row(c)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(c) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索姓名/邮箱")
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.load() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Label("添加候选人", systemImage: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            HiringCandidateEditSheet(
                existing: nil,
                positions: viewModel.positions
            ) {
                Task { await viewModel.load() }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .zyErrorBanner($viewModel.errorMessage)
    }

    @ViewBuilder
    private func row(_ c: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(c.fullName)
                    .font(.headline)
                Spacer()
                statusBadge(c.status)
            }
            HStack(spacing: 8) {
                if let title = c.jobPositions?.title, !title.isEmpty {
                    Label(title, systemImage: "briefcase")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let score = c.aiScore {
                    Label("AI \(score)", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(scoreColor(score))
                }
            }
            if let email = c.email, !email.isEmpty {
                Text(email)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(_ status: Candidate.CandidateStatus) -> some View {
        Text(status.displayLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color(for: status).opacity(0.15))
            .foregroundStyle(color(for: status))
            .clipShape(Capsule())
    }

    private func color(for status: Candidate.CandidateStatus) -> Color {
        switch status {
        case .new:        return .secondary
        case .screening:  return .blue
        case .interview:  return .orange
        case .offer:      return .green
        case .hired:      return .green
        case .onboarding: return .teal
        case .completed:  return .secondary
        case .rejected:   return .red
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }
}
