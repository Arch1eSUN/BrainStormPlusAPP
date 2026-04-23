import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// Phase 2.1 — Deliverables create sheet.
//
// 1:1 port of the "新建交付物" dialog in
// `BrainStorm+-Web/src/app/dashboard/deliverables/page.tsx:199-254`.
// Web surfaces exactly 4 inputs:
//   • 名称        (title)           required
//   • 交付链接     (url)             required on Web (`!form.url.trim()`
//                                    disables submit), optional in the DB
//   • 关联项目     (project_id)      optional, dropdown of projects
//   • 备注        (description)     optional, 2-row textarea
//
// Server fills the rest (`status='submitted'`, `assignee_id`, `org_id`,
// `submitted_at=now()`) — see `createDeliverable` in
// `BrainStorm+-Web/src/lib/actions/deliverables.ts:97-127` and the iOS
// twin in DeliverableListViewModel.createDeliverable.
//
// Intentionally NOT in this sheet — owner picker, due date, priority,
// attachments: none of those exist on Web's create surface (they're
// either auto-filled, absent from the schema, or live on the edit
// surface/detail view).
// ══════════════════════════════════════════════════════════════════

public struct DeliverableCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DeliverableListViewModel

    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var url: String = ""
    @State private var projectId: UUID? = nil
    @State private var localError: String? = nil
    @State private var isSubmitting: Bool = false

    public init(viewModel: DeliverableListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                detailsSection
                linkSection
                projectSection
                noteSection

                if let message = localError {
                    Section {
                        Text(message)
                            .font(BsTypography.caption)
                            .foregroundColor(BsColor.danger)
                    }
                }
            }
            .navigationTitle("新建交付物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .font(BsTypography.inter(16, weight: "Medium"))
                        .foregroundColor(BsColor.inkMuted)
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("提交") {
                        Task { await submit() }
                    }
                    .font(BsTypography.inter(16, weight: "SemiBold"))
                    .foregroundColor(isSaveEnabled ? BsColor.brandAzure : BsColor.inkMuted)
                    .disabled(!isSaveEnabled)
                }
            }
            .overlay {
                if isSubmitting {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        ProgressView()
                            .padding()
                            .background(BsColor.surfacePrimary)
                            .cornerRadius(BsRadius.md)
                            .shadow(radius: 8)
                    }
                }
            }
        }
    }

    // MARK: - Derived

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUrl: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Matches Web's enable rule — both title and URL must be present.
    /// See page.tsx:249 (`disabled={creating || !form.title.trim() || !form.url.trim()}`).
    private var isSaveEnabled: Bool {
        !trimmedTitle.isEmpty && !trimmedUrl.isEmpty && !isSubmitting
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section(header: sectionHeader("名称")) {
            TextField("交付物名称", text: $title)
                .font(BsTypography.inter(16, weight: "Regular"))
                .disabled(isSubmitting)
        }
    }

    private var linkSection: some View {
        Section(header: sectionHeader("交付链接")) {
            TextField(
                "粘贴 Google Drive / 百度网盘 / 夸克网盘链接",
                text: $url
            )
            .font(BsTypography.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .keyboardType(.URL)
            .disabled(isSubmitting)

            if !trimmedUrl.isEmpty, let platform = DeliverablePlatform.detect(trimmedUrl) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.caption2)
                    Text(platform.label)
                        .font(BsTypography.captionSmall)
                }
                .foregroundColor(platform.color)
            }
        }
    }

    private var projectSection: some View {
        Section(header: sectionHeader("关联项目")) {
            Menu {
                Button("不关联项目") { projectId = nil }
                ForEach(viewModel.projects, id: \.id) { p in
                    if let pid = p.id {
                        Button(p.name ?? "(未命名)") { projectId = pid }
                    }
                }
            } label: {
                HStack {
                    Text(projectLabel)
                        .font(BsTypography.body)
                        .foregroundColor(projectId == nil ? BsColor.inkMuted : BsColor.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(BsColor.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .disabled(isSubmitting)
        }
    }

    private var noteSection: some View {
        Section(header: sectionHeader("备注")) {
            TextField(
                "简要说明交付内容（可选）",
                text: $descriptionText,
                axis: .vertical
            )
            .font(BsTypography.body)
            .lineLimit(2...5)
            .disabled(isSubmitting)
        }
    }

    private var projectLabel: String {
        guard let pid = projectId else { return "不关联项目" }
        return viewModel.projects.first(where: { $0.id == pid })?.name ?? "不关联项目"
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(BsTypography.caption)
            .foregroundColor(BsColor.inkMuted)
    }

    // MARK: - Submit

    private func submit() async {
        guard isSaveEnabled else { return }
        localError = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let ok = await viewModel.createDeliverable(
            title: trimmedTitle,
            description: descriptionText,
            url: trimmedUrl,
            projectId: projectId
        )
        if ok {
            dismiss()
        } else {
            // VM surfaces the message on its `errorMessage` banner; mirror it
            // inline in the sheet so the user doesn't lose context after the
            // sheet dismisses.
            localError = viewModel.errorMessage
        }
    }
}
