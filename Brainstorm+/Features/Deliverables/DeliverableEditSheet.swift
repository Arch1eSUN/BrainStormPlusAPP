import SwiftUI
import Supabase

// ══════════════════════════════════════════════════════════════════
// DeliverableEditSheet — full-row edit surface.
//
// Mirrors Web's inline edit behavior in `updateDeliverable` at
// BrainStorm+-Web/src/lib/actions/deliverables.ts:131-153. Web edits
// the row via its list page row menu; iOS invokes this sheet from the
// detail view (ellipsis menu) and from list context/swipe actions.
//
// Partial-update contract:
//   • Only fields whose value differs from the original are sent; the
//     rest are omitted (VM treats `nil` as "leave as-is", matching
//     Web's `updates.field !== undefined` gate).
//   • Clearing `description`/`url` by emptying the input sends `""`,
//     which the VM maps to `NULL`.
//   • Project picker supports an explicit "不关联项目" option that flips
//     the `clearProject` flag so the VM emits `project_id = NULL`
//     (Web ternary `updates.project_id || null`).
// ══════════════════════════════════════════════════════════════════

public struct DeliverableEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DeliverableListViewModel

    private let original: Deliverable

    @State private var title: String
    @State private var descriptionText: String
    @State private var urlText: String
    @State private var projectId: UUID?
    @State private var status: Deliverable.DeliverableStatus
    @State private var localError: String? = nil
    @State private var isSaving: Bool = false

    /// `onSaved` lets the caller react (e.g. refresh detail VM) once the
    /// VM reports success. Optional — list-side callers can ignore it.
    private let onSaved: ((Deliverable) -> Void)?

    public init(
        viewModel: DeliverableListViewModel,
        deliverable: Deliverable,
        onSaved: ((Deliverable) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.original = deliverable
        self.onSaved = onSaved
        _title = State(initialValue: deliverable.title)
        _descriptionText = State(initialValue: deliverable.description ?? "")
        _urlText = State(initialValue: deliverable.url ?? deliverable.fileUrl ?? "")
        _projectId = State(initialValue: deliverable.projectId)
        _status = State(initialValue: deliverable.status)
    }

    public var body: some View {
        NavigationStack {
            Form {
                titleSection
                linkSection
                projectSection
                statusSection
                noteSection

                if let message = localError {
                    Section {
                        Text(message)
                            .font(BsTypography.caption)
                            .foregroundColor(BsColor.danger)
                    }
                }
            }
            .navigationTitle("编辑交付物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        // Haptic removed: 用户反馈辅助按钮过密震动
                        dismiss()
                    }
                    .font(BsTypography.inter(16, weight: "Medium", relativeTo: .callout))
                    .foregroundColor(BsColor.inkMuted)
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        Haptic.medium()
                        Task { await submit() }
                    }
                    .font(BsTypography.inter(16, weight: "SemiBold", relativeTo: .callout))
                    .foregroundColor(isSaveEnabled ? BsColor.brandAzure : BsColor.inkMuted)
                    .disabled(!isSaveEnabled)
                }
            }
            .overlay {
                if isSaving {
                    ZStack {
                        // Raw Color.black scrim —— 系统标准 modal 遮罩背景色。
                        Color.black.opacity(0.35).ignoresSafeArea()
                        ProgressView()
                            .padding(BsSpacing.md)
                            .background(BsColor.surfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                            .bsShadow(BsShadow.md)
                    }
                }
            }
        }
    }

    // MARK: - Derived

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSaveEnabled: Bool {
        !trimmedTitle.isEmpty && hasChanges && !isSaving
    }

    /// Any field different from `original`? Matches Web semantics — the
    /// inline edit only dispatches an update when something actually
    /// changed (otherwise the `.update(...)` call would be a no-op round
    /// trip).
    private var hasChanges: Bool {
        trimmedTitle != original.title
            || normalize(descriptionText) != normalize(original.description ?? "")
            || normalize(urlText) != normalize(original.url ?? original.fileUrl ?? "")
            || projectId != original.projectId
            || status != original.status
    }

    private func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Sections

    private var titleSection: some View {
        Section(header: sectionHeader("名称")) {
            TextField("交付物名称", text: $title)
                .font(BsTypography.inter(16, weight: "Regular", relativeTo: .callout))
                .disabled(isSaving)
        }
    }

    private var linkSection: some View {
        Section(header: sectionHeader("交付链接")) {
            TextField(
                "粘贴 Google Drive / 百度网盘 / 夸克网盘链接",
                text: $urlText
            )
            .font(BsTypography.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .keyboardType(.URL)
            .disabled(isSaving)

            let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let platform = DeliverablePlatform.detect(trimmed) {
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
                Button("不关联项目") {
                    // Haptic removed: menu 选项过密震动
                    projectId = nil
                }
                ForEach(viewModel.projects, id: \.id) { p in
                    if let pid = p.id {
                        Button(p.name ?? "(未命名)") {
                            // Haptic removed: menu 选项过密震动
                            projectId = pid
                        }
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
            .disabled(isSaving)
        }
    }

    private var statusSection: some View {
        Section(header: sectionHeader("状态")) {
            Menu {
                ForEach(Deliverable.DeliverableStatus.allCases, id: \.self) { s in
                    Button {
                        // Haptic removed: menu 选项过密震动
                        status = s
                    } label: {
                        HStack {
                            Text(s.displayName)
                            if s == status {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(status.displayName)
                        .font(BsTypography.body)
                        .foregroundColor(BsColor.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(BsColor.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .disabled(isSaving)
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
            .lineLimit(3...6)
            .disabled(isSaving)
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
        isSaving = true
        defer { isSaving = false }

        // Compute diff vs. original — only pass changed fields, so the
        // VM can thread them through as "undefined" (skip) for the rest.
        let titleArg: String? = (trimmedTitle != original.title) ? trimmedTitle : nil

        let descArg: String? = {
            let newVal = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            let oldVal = (original.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return newVal == oldVal ? nil : newVal   // "" → VM clears to null
        }()

        let urlArg: String? = {
            let newVal = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            let oldVal = (original.url ?? original.fileUrl ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return newVal == oldVal ? nil : newVal   // "" → VM clears to null
        }()

        // Project three-way: nil+clearProject=false → skip;
        //                    nil+clearProject=true  → set NULL;
        //                    UUID                   → set value.
        var projectIdArg: UUID? = nil
        var clearProjectArg: Bool = false
        if projectId != original.projectId {
            if let pid = projectId {
                projectIdArg = pid
            } else {
                clearProjectArg = true
            }
        }

        let statusArg: Deliverable.DeliverableStatus? =
            (status != original.status) ? status : nil

        let ok = await viewModel.updateDeliverable(
            id: original.id,
            title: titleArg,
            description: descArg,
            url: urlArg,
            projectId: projectIdArg,
            clearProject: clearProjectArg,
            status: statusArg
        )

        if ok {
            if let refreshed = viewModel.items.first(where: { $0.id == original.id }) {
                onSaved?(refreshed)
            }
            dismiss()
        } else {
            localError = viewModel.errorMessage
        }
    }
}
