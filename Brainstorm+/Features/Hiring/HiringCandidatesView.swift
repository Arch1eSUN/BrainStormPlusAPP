import SwiftUI

public struct HiringCandidatesView: View {
    @StateObject private var viewModel = HiringCandidatesViewModel()
    @State private var showCreate: Bool = false
    @State private var pushTarget: Candidate? = nil

    /// iOS 18+ zoom transition source namespace — Apple Mail / Photos
    /// row→detail morph.
    @Namespace private var zoomNamespace

    public init() {}

    public var body: some View {
        // Bug-fix(Hiring tab jump): ZStack 撑满 + ProgressView 用 .large + frame fill，
        // 避免 loading/empty 时子 view 高度坍塌,触发外层 Picker 位移 / nav 抖动。
        ZStack {
            if viewModel.isLoading && viewModel.candidates.isEmpty {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.candidates.isEmpty {
                BsEmptyState(
                    title: "暂无候选人",
                    systemImage: "person.crop.square.filled.and.at.rectangle",
                    description: "点击右上角「添加候选人」开始录入。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.candidates) { c in
                        Button {
                            pushTarget = c
                        } label: {
                            row(c)
                                .matchedTransitionSource(id: c.id, in: zoomNamespace)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                // Haptic removed: swipe action 系统自带反馈
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
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索姓名/邮箱"
        )
        .navigationDestination(item: $pushTarget) { c in
            HiringCandidateDetailView(candidateId: c.id) {
                Task { await viewModel.load() }
            }
            .navigationTransition(.zoom(sourceID: c.id, in: zoomNamespace))
        }
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.load() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Haptic removed: 用户反馈 toolbar 按钮过密震动
                    showCreate = true
                } label: {
                    Label("添加候选人", systemImage: "person.badge.plus")
                }
                .accessibilityLabel("添加候选人")
            }
        }
        .sheet(isPresented: $showCreate) {
            HiringCandidateEditSheet(
                existing: nil,
                positions: viewModel.positions
            ) {
                Task { await viewModel.load() }
            }
            .bsSheetStyle(.form)
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
                        .foregroundStyle(BsColor.inkMuted)
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
                    .foregroundStyle(BsColor.inkMuted)
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
        case .new:        return BsColor.inkMuted
        case .screening:  return BsColor.brandAzure
        case .interview:  return BsColor.warning
        case .offer:      return BsColor.success
        case .hired:      return BsColor.success
        case .onboarding: return BsColor.brandMint
        case .completed:  return BsColor.inkMuted
        case .rejected:   return BsColor.danger
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return BsColor.success }
        if score >= 60 { return BsColor.warning }
        return BsColor.danger
    }
}
