import SwiftUI

public struct HiringCandidateDetailView: View {
    @StateObject private var viewModel: HiringCandidateDetailViewModel
    @State private var showEdit: Bool = false

    /// AI 评分时选的 position（默认用 candidate.positionId；候选人没关联职位时让 HR 手选）
    @State private var scoringPositionId: UUID?

    private let onChanged: () -> Void

    public init(candidateId: UUID, onChanged: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: HiringCandidateDetailViewModel(candidateId: candidateId))
        self.onChanged = onChanged
    }

    public var body: some View {
        candidateContent
    }

    // MARK: - Body content（拆出来避免主 body 类型推断超时）

    @ViewBuilder
    private var candidateContent: some View {
        Group {
            if let candidate = viewModel.candidate {
                candidateScrollView(candidate)
            } else if viewModel.isLoading {
                ProgressView().padding(.top, 40)
            } else {
                ContentUnavailableView(
                    "候选人不存在",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("该候选人可能已被删除。")
                )
            }
        }
        .navigationTitle(viewModel.candidate?.fullName ?? "候选人")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { showEdit = true }
                    .disabled(viewModel.candidate == nil)
            }
        }
        .sheet(isPresented: $showEdit) {
            if let candidate = viewModel.candidate {
                HiringCandidateEditSheet(
                    existing: candidate,
                    positions: viewModel.positions
                ) {
                    Task {
                        await viewModel.load()
                        onChanged()
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .zyErrorBanner($viewModel.errorMessage)
        .confirmationDialog(
            "要同时发送 Offer 邮件吗？",
            isPresented: $viewModel.pendingOfferConfirmation,
            titleVisibility: .visible
        ) {
            Button("发送") {
                Task { await viewModel.sendOfferEmail() }
            }
            Button("仅更新状态", role: .cancel) {}
        } message: {
            Text("候选人已进入 Offer 阶段，是否立即发送 Offer 邮件？")
        }
        .overlay(alignment: .top) {
            if let toast = viewModel.toastMessage {
                OfferToastView(text: toast)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        await MainActor.run { viewModel.toastMessage = nil }
                    }
            }
        }
        .animation(BsMotion.Anim.smooth, value: viewModel.toastMessage)
    }

    @ViewBuilder
    private func candidateScrollView(_ candidate: Candidate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(candidate)
                contactSection(candidate)
                statusSection(candidate)
                aiReviewSection(candidate)
                resumeScoreSection(candidate)
                resumeSection(candidate)
                notesSection(candidate)
            }
            .padding()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func header(_ c: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.fullName)
                .font(.title2.weight(.bold))
            if let title = c.jobPositions?.title, !title.isEmpty {
                Label(title, systemImage: "briefcase")
                    .font(.subheadline)
                    .foregroundStyle(BsColor.inkMuted)
            }
        }
    }

    @ViewBuilder
    private func contactSection(_ c: Candidate) -> some View {
        card(title: "联系方式") {
            if (c.email ?? "").isEmpty && (c.phone ?? "").isEmpty {
                Text("未填写").font(.caption).foregroundStyle(BsColor.inkMuted)
            } else {
                if let email = c.email, !email.isEmpty {
                    Label(email, systemImage: "envelope")
                        .font(.subheadline)
                }
                if let phone = c.phone, !phone.isEmpty {
                    Label(phone, systemImage: "phone")
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private func statusSection(_ c: Candidate) -> some View {
        card(title: "跟进状态") {
            HStack {
                Text(c.status.displayLabel)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(color(for: c.status).opacity(0.15))
                    .foregroundStyle(color(for: c.status))
                    .clipShape(Capsule())
                Spacer()
                if !c.status.allowedNext.isEmpty {
                    Menu {
                        ForEach(c.status.allowedNext, id: \.self) { next in
                            Button(action: {
                                Task {
                                    await viewModel.transition(to: next)
                                    onChanged()
                                }
                            }) {
                                Label(next.displayLabel, systemImage: icon(for: next))
                            }
                        }
                    } label: {
                        Label("推进状态", systemImage: "arrow.right.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func aiReviewSection(_ c: Candidate) -> some View {
        if c.aiScore != nil || viewModel.aiReview != nil {
            card(title: "AI 简历审查") {
                VStack(alignment: .leading, spacing: 10) {
                    if let score = c.aiScore {
                        HStack {
                            Text("评分")
                                .font(.caption)
                                .foregroundStyle(BsColor.inkMuted)
                            Text("\(score)")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(scoreColor(score))
                            Spacer()
                        }
                    }
                    if let review = viewModel.aiReview {
                        if !review.summary.isEmpty {
                            Text(review.summary)
                                .font(.subheadline)
                                .foregroundStyle(BsColor.ink)
                        }
                        aiBulletBlock(title: "匹配点", items: review.matchItems, systemImage: "checkmark.circle", tint: BsColor.success)
                        aiBulletBlock(title: "优势", items: review.strengths, systemImage: "star.fill", tint: BsColor.warning)
                        aiBulletBlock(title: "缺口", items: review.gapItems, systemImage: "exclamationmark.triangle", tint: BsColor.warning)
                        aiBulletBlock(title: "风险", items: review.riskPoints, systemImage: "exclamationmark.octagon", tint: BsColor.danger)
                        aiBulletBlock(title: "人工复核", items: review.manualReviewItems, systemImage: "person.fill.questionmark", tint: BsColor.brandAzure)  // TODO(batch-3): evaluate .purple → brandAzure
                        aiBulletBlock(title: "顾虑", items: review.concerns, systemImage: "questionmark.circle", tint: BsColor.inkMuted)
                    }
                    Text("AI 审查由 Web 端触发；iOS 仅呈现已保存的审查结果。")
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkFaint)
                }
            }
        }
    }

    // MARK: - AI 简历评分（触发 /api/mobile/hiring/score）

    @ViewBuilder
    private func resumeScoreSection(_ c: Candidate) -> some View {
        let effectivePositionId = scoringPositionId ?? c.positionId

        card(title: "AI 简历评分") {
            VStack(alignment: .leading, spacing: 12) {
                if c.positionId == nil {
                    resumeScorePositionPicker(effectivePositionId: effectivePositionId)
                }
                if let score = viewModel.resumeScore {
                    resumeScoreResultCard(score)
                }
                resumeScoreTriggerButton(positionId: effectivePositionId)
                if effectivePositionId == nil {
                    Text("请先为候选人选择评估职位")
                        .font(.caption2)
                        .foregroundStyle(BsColor.warning)
                }
                Text("由 Web AI orchestrator 生成；评分依据候选人简历与所选职位要求匹配度。历史记录写入 resume_scores 表。")
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkFaint)
            }
        }
    }

    @ViewBuilder
    private func resumeScorePositionPicker(effectivePositionId: UUID?) -> some View {
        HStack {
            Text("评估职位")
                .font(.caption)
                .foregroundStyle(BsColor.inkMuted)
            Spacer()
            Menu {
                ForEach(viewModel.positions) { pos in
                    Button(pos.title) {
                        Haptic.selection()
                        scoringPositionId = pos.id
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(positionTitle(for: effectivePositionId) ?? "选择职位")
                        .font(.subheadline)
                        .foregroundStyle(effectivePositionId == nil ? BsColor.inkMuted : BsColor.ink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkFaint)
                }
            }
        }
    }

    @ViewBuilder
    private func resumeScoreResultCard(_ score: HiringCandidateDetailViewModel.ResumeScoreResult) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(score.score)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(score.score))
                Text("/ 100")
                    .font(.title3)
                    .foregroundStyle(BsColor.inkFaint)
                Spacer()
                Text(score.recommendation)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, BsSpacing.sm)
                    .padding(.vertical, BsSpacing.xs)
                    .background(Capsule().fill(scoreColor(score.score).opacity(0.15)))
                    .foregroundStyle(scoreColor(score.score))
            }
            aiBulletBlock(title: "优势", items: score.strengths, systemImage: "star.fill", tint: BsColor.success)
            aiBulletBlock(title: "不足", items: score.weaknesses, systemImage: "exclamationmark.triangle", tint: BsColor.warning)
            if let model = score.modelUsed {
                Text("模型：\(model)")
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkFaint)
            }
        }
    }

    @ViewBuilder
    private func resumeScoreTriggerButton(positionId: UUID?) -> some View {
        let buttonLabel: String = {
            if viewModel.isScoringResume { return "评分中…" }
            return viewModel.resumeScore == nil ? "生成 AI 评分" : "重新评分"
        }()
        let isDisabled = positionId == nil || viewModel.isScoringResume
        let fillColor: Color = isDisabled ? BsColor.inkMuted.opacity(0.3) : BsColor.brandAzure

        Button {
            guard let posId = positionId else { return }
            Haptic.medium()
            Task { await viewModel.scoreResume(positionId: posId) }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isScoringResume {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(buttonLabel)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, BsSpacing.sm)
            .background(RoundedRectangle(cornerRadius: BsRadius.md).fill(fillColor))
            .foregroundStyle(.white)
        }
        .disabled(isDisabled)
        .accessibilityLabel(viewModel.resumeScore == nil ? "生成 AI 简历评分" : "重新生成 AI 简历评分")
    }

    private func positionTitle(for id: UUID?) -> String? {
        guard let id = id else { return nil }
        return viewModel.positions.first(where: { $0.id == id })?.title
    }

    @ViewBuilder
    private func resumeSection(_ c: Candidate) -> some View {
        if let text = c.resumeText, !text.isEmpty {
            card(title: "简历内容") {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(BsColor.ink)
            }
        }
        if let url = c.resumeUrl, !url.isEmpty, let resolved = URL(string: url) {
            card(title: "简历附件") {
                Link(destination: resolved) {
                    Label("打开附件", systemImage: "doc.richtext")
                }
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ c: Candidate) -> some View {
        if let notes = c.notes, !notes.isEmpty {
            card(title: "备注") {
                Text(notes)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Utilities

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BsColor.inkMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func aiBulletBlock(title: String, items: [String], systemImage: String, tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.caption)
                        .foregroundStyle(BsColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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

    private func icon(for status: Candidate.CandidateStatus) -> String {
        switch status {
        case .new:        return "sparkles"
        case .screening:  return "magnifyingglass"
        case .interview:  return "person.2"
        case .offer:      return "envelope.open"
        case .hired:      return "checkmark.seal"
        case .onboarding: return "arrow.right.doc.on.clipboard"
        case .completed:  return "checkmark.circle"
        case .rejected:   return "xmark.circle"
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return BsColor.success }
        if score >= 60 { return BsColor.warning }
        return BsColor.danger
    }
}

private struct OfferToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.white)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(BsColor.success.gradient)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}
