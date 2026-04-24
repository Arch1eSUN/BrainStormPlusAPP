import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 2.1 — Deliverable detail view.
//
// Surface (matches the row expansion implied by the Web page):
//   • Title + owner avatar (join from `profiles:assignee_id`)
//   • Status chip + status picker (5 primary cases)
//   • Description body
//   • External link chip → opens `url` / `file_url` in Safari
//   • Project pill (nested join `projects:project_id`)
//   • Submitted / created / updated timestamps
//
// Out of scope this pass (mirrors the list view):
//   • Edit / delete (TODO when the Web CRUD flow gets ported).
//   • Participants join — Web deliverables row has no participants
//     table; if one is introduced later, add it here alongside the
//     owner avatar.
// ══════════════════════════════════════════════════════════════════

public struct DeliverableDetailView: View {
    @StateObject private var viewModel: DeliverableDetailViewModel

    public init(viewModel: DeliverableDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusSection
                if let url = linkURL {
                    linkCard(url: url)
                }
                if let desc = viewModel.deliverable.description, !desc.isEmpty {
                    section(title: "描述") {
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let project = viewModel.deliverable.project {
                    section(title: "关联项目") {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                            Text(project.name ?? "未命名项目")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                if let assignee = viewModel.deliverable.assignee {
                    section(title: "负责人") {
                        assigneeRow(assignee)
                    }
                }
                timestampsCard
            }
            .padding()
        }
        .navigationTitle("交付物详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refresh()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .zyErrorBanner($viewModel.errorMessage)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.deliverable.title)
                .font(.title3.weight(.bold))
            HStack(spacing: 8) {
                DeliverableStatusChip(status: viewModel.deliverable.status)
                if let submitted = viewModel.deliverable.submittedAt {
                    Label {
                        Text(submitted, style: .date)
                    } icon: {
                        Image(systemName: "paperplane.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Status picker

    @ViewBuilder
    private var statusSection: some View {
        section(title: "状态") {
            Menu {
                ForEach(Deliverable.DeliverableStatus.primaryCases, id: \.self) { s in
                    Button {
                        Task { await viewModel.updateStatus(s) }
                    } label: {
                        HStack {
                            Text(s.displayName)
                            if s == viewModel.deliverable.status {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.deliverable.status.displayName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if viewModel.isMutating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(viewModel.isMutating)
        }
    }

    // MARK: - Link card

    private var linkURL: URL? {
        let raw = viewModel.deliverable.url
            ?? viewModel.deliverable.fileUrl
            ?? ""
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    @ViewBuilder
    private func linkCard(url: URL) -> some View {
        section(title: "交付链接") {
            let platform = DeliverablePlatform.detect(url.absoluteString)
                ?? DeliverablePlatform(label: "链接", color: .gray)
            Link(destination: url) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.right.square.fill")
                        .foregroundStyle(platform.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(platform.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(url.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(platform.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    // MARK: - Assignee

    @ViewBuilder
    private func assigneeRow(_ assignee: Deliverable.RelatedProfile) -> some View {
        HStack(spacing: 12) {
            Group {
                if let urlStr = assignee.avatarUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.15)
                    }
                } else {
                    Circle().fill(Color.accentColor.opacity(0.2))
                        .overlay {
                            Text((assignee.fullName ?? "?").prefix(1))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            Text(assignee.fullName ?? "未命名")
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
    }

    // MARK: - Timestamps

    @ViewBuilder
    private var timestampsCard: some View {
        BsContentCard(padding: .small) {
            VStack(alignment: .leading, spacing: 6) {
                if let created = viewModel.deliverable.createdAt {
                    timestampRow(label: "创建时间", date: created)
                }
                if let updated = viewModel.deliverable.updatedAt,
                   updated != viewModel.deliverable.createdAt {
                    timestampRow(label: "更新时间", date: updated)
                }
            }
        }
    }

    @ViewBuilder
    private func timestampRow(label: String, date: Date) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(date, style: .date)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Section helper

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}
