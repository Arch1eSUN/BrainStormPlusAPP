import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Deliverable detail view.
//
// Surface:
//   • Title + owner avatar (join from `profiles:assignee_id`)
//   • Status chip + status picker (5 primary cases)
//   • Description body
//   • External link chip → opens `url` / `file_url` in Safari
//   • Project pill (nested join `projects:project_id`)
//   • Submitted / created / updated timestamps
//   • Toolbar ellipsis menu: 编辑 / 删除（CRUD 于 0d3dfad 上线）
// ══════════════════════════════════════════════════════════════════

public struct DeliverableDetailView: View {
    @StateObject private var viewModel: DeliverableDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false

    public init(viewModel: DeliverableDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.lg + BsSpacing.xs) { // 20pt section rhythm
                header
                statusSection
                if let url = linkURL {
                    linkCard(url: url)
                }
                if let desc = viewModel.deliverable.description, !desc.isEmpty {
                    section(title: "描述") {
                        BsContentCard(padding: .small) {
                            Text(desc)
                                .font(.body)
                                .foregroundStyle(BsColor.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if let project = viewModel.deliverable.project {
                    section(title: "关联项目") {
                        BsContentCard(padding: .small) {
                            HStack(spacing: BsSpacing.sm) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(BsColor.brandAzure)
                                Text(project.name ?? "未命名项目")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BsColor.ink)
                            }
                        }
                    }
                }
                if let assignee = viewModel.deliverable.assignee {
                    section(title: "负责人") {
                        BsContentCard(padding: .small) {
                            assigneeRow(assignee)
                        }
                    }
                }
                timestampsCard
            }
            .padding(BsSpacing.lg)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
        .navigationTitle("交付物详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Haptic.light()
                        showEditSheet = true
                    } label: {
                        Label("编辑交付物", systemImage: "pencil")
                    }
                    .disabled(viewModel.listViewModel == nil)

                    Button(role: .destructive) {
                        Haptic.warning()
                        showDeleteConfirm = true
                    } label: {
                        Label("删除交付物", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(BsColor.brandAzure)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("更多操作")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let list = viewModel.listViewModel {
                DeliverableEditSheet(
                    viewModel: list,
                    deliverable: viewModel.deliverable,
                    onSaved: { fresh in
                        viewModel.apply(fresh)
                    }
                )
            }
        }
        .confirmationDialog(
            "删除后该交付物记录无法恢复，确认？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task {
                    let ok = await viewModel.deleteCurrent()
                    if ok { dismiss() }
                }
            }
            Button("取消", role: .cancel) {}
        }
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
        BsContentCard {
            VStack(alignment: .leading, spacing: BsSpacing.sm) {
                Text(viewModel.deliverable.title)
                    .font(BsTypography.sectionTitle)
                    .foregroundStyle(BsColor.ink)
                HStack(spacing: BsSpacing.sm) {
                    DeliverableStatusChip(status: viewModel.deliverable.status)
                    if let submitted = viewModel.deliverable.submittedAt {
                        Label {
                            Text(submitted, style: .date)
                        } icon: {
                            Image(systemName: "paperplane.fill")
                        }
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BsColor.inkMuted)
                    }
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
                        Haptic.selection()
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
                        .foregroundStyle(BsColor.ink)
                    Spacer()
                    if viewModel.isMutating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }
                .padding(.horizontal, BsSpacing.md)
                .padding(.vertical, BsSpacing.smd)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BsColor.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .stroke(BsColor.borderSubtle, lineWidth: 0.5)
                )
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
            // TODO(batch-3): vendor platform colors — define BsColor.platform namespace later
            // Intentional: platform.color 是外部品牌色（Google Drive / 百度网盘 /
            // Figma / GitHub / ...），保留不走 token —— vendor color 是辨识关键。
            let platform = DeliverablePlatform.detect(url.absoluteString)
                ?? DeliverablePlatform(label: "链接", color: BsColor.inkMuted)
            Link(destination: url) {
                HStack(spacing: BsSpacing.smd) {
                    Image(systemName: "arrow.up.right.square.fill")
                        .foregroundStyle(platform.color)
                    VStack(alignment: .leading, spacing: BsSpacing.xxs) {
                        Text(platform.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BsColor.ink)
                        Text(url.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(BsColor.inkMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkFaint)
                }
                .padding(BsSpacing.md)
                .background(platform.color.opacity(0.08))  // vendor tint
                .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
            }
        }
    }

    // MARK: - Assignee

    @ViewBuilder
    private func assigneeRow(_ assignee: Deliverable.RelatedProfile) -> some View {
        HStack(spacing: BsSpacing.md) {
            Group {
                if let urlStr = assignee.avatarUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        BsColor.inkMuted.opacity(0.15)
                    }
                } else {
                    Circle().fill(BsColor.brandAzure.opacity(0.2))
                        .overlay {
                            Text((assignee.fullName ?? "?").prefix(1))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BsColor.brandAzure)
                        }
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .accessibilityLabel(assignee.fullName ?? "用户")

            Text(assignee.fullName ?? "未命名")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BsColor.ink)
            Spacer()
        }
    }

    // MARK: - Timestamps

    @ViewBuilder
    private var timestampsCard: some View {
        BsContentCard(padding: .small) {
            VStack(alignment: .leading, spacing: BsSpacing.xs + 2) { // 6pt row gap
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
                .foregroundStyle(BsColor.inkMuted)
            Spacer()
            Text(date, style: .date)
                .font(.caption)
                .foregroundStyle(BsColor.ink)
        }
    }

    // MARK: - Section helper

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            Text(title)
                .font(BsTypography.label)
                .foregroundStyle(BsColor.inkMuted)
                .textCase(.uppercase)
            content()
        }
    }
}
