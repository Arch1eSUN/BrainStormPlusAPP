import SwiftUI

/// Shared create/edit sheet for `Objective`. Mirrors Web's single dialog
/// that toggles between create and edit based on `editingObjectiveId`
/// (`BrainStorm+-Web/src/app/dashboard/okr/page.tsx:195-225`).
///
/// Usage:
/// - Create:  `OKREditSheet(existing: nil, viewModel: vm, onDismiss: …)`
/// - Edit:    `OKREditSheet(existing: obj, viewModel: vm, onDismiss: …)`
///
/// Writes are routed through `OKRListViewModel.createObjective` /
/// `updateObjective`, both of which refresh the published list on success.
public struct OKREditSheet: View {
    public let existing: Objective?
    public let viewModel: OKRListViewModel
    public let onDismiss: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var period: String
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, description, period }

    public init(
        existing: Objective?,
        viewModel: OKRListViewModel,
        onDismiss: @escaping () -> Void
    ) {
        self.existing = existing
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        // Seed period from either the existing objective or the VM's
        // currently-selected quarter.
        _period = State(initialValue: existing?.period ?? viewModel.period)
    }

    private var isEditing: Bool { existing != nil }
    private var screenTitle: String { isEditing ? "编辑 OKR" : "新建 OKR" }
    private var submitLabel: String { isEditing ? "保存修改" : "创建" }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedTitle.isEmpty && !isSubmitting
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BsColor.surfaceSecondary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: BsSpacing.lg) {
                        titleField
                        descriptionField
                        periodField
                        // Owner field skipped for this first pass —
                        // objective defaults to the current authenticated
                        // user. TODO: add owner/assignee picker once the
                        // profile list endpoint is wired up for OKRs
                        // (Web's `fetchTeamMembers` equivalent).
                        ownerNote

                        BsPrimaryButton(
                            submitLabel,
                            size: .large,
                            isLoading: isSubmitting,
                            isDisabled: !canSubmit
                        ) {
                            submit()
                        }
                        .padding(.top, BsSpacing.sm)

                        Spacer(minLength: BsSpacing.xl)
                    }
                    .padding(.horizontal, BsSpacing.lg + 4)
                    .padding(.top, BsSpacing.md)
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        onDismiss()
                    }
                    .tint(BsColor.inkMuted)
                }
            }
            .onAppear {
                if let existing = existing {
                    title = existing.title
                    description = existing.description ?? ""
                }
                focusedField = .title
            }
            .alert(
                "操作失败",
                isPresented: .init(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            fieldLabel("目标名称", required: true)
            TextField("如：提升客户满意度", text: $title, axis: .horizontal)
                .focused($focusedField, equals: .title)
                .textFieldStyle(.plain)
                .font(BsTypography.inter(15, weight: "Regular"))
                .foregroundColor(BsColor.ink)
                .padding(BsSpacing.md)
                .background(BsColor.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .stroke(BsColor.borderSubtle, lineWidth: 0.5)
                )
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            fieldLabel("描述", required: false)
            TextField(
                "可选 · 简要描述这个目标希望达成的结果",
                text: $description,
                axis: .vertical
            )
            .focused($focusedField, equals: .description)
            .lineLimit(3...6)
            .textFieldStyle(.plain)
            .font(BsTypography.inter(14, weight: "Regular"))
            .foregroundColor(BsColor.ink)
            .padding(BsSpacing.md)
            .background(BsColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
            )
        }
    }

    private var periodField: some View {
        let parsed = OKRListViewModel.parsePeriod(period)
            ?? (Calendar.current.component(.year, from: Date()), 1)

        return VStack(alignment: .leading, spacing: BsSpacing.xs) {
            fieldLabel("周期", required: false)
            HStack(spacing: BsSpacing.sm) {
                // Year
                Menu {
                    ForEach(viewModel.availableYears, id: \.self) { year in
                        Button(String(year)) {
                            period = OKRListViewModel.formatPeriod(
                                year: year,
                                quarter: parsed.quarter
                            )
                        }
                    }
                } label: {
                    pickerPill(label: String(parsed.year))
                }

                // Quarter
                Menu {
                    ForEach(viewModel.availableQuarters, id: \.self) { q in
                        Button("Q\(q)") {
                            period = OKRListViewModel.formatPeriod(
                                year: parsed.year,
                                quarter: q
                            )
                        }
                    }
                } label: {
                    pickerPill(label: "Q\(parsed.quarter)")
                }

                Spacer()
            }
        }
    }

    private var ownerNote: some View {
        HStack(alignment: .top, spacing: BsSpacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(BsColor.brandAzure.opacity(0.7))
            Text("默认负责人为当前登录用户。如需改派他人，请到 Web 端调整。")
                .font(BsTypography.inter(11, weight: "Regular"))
                .foregroundColor(BsColor.inkMuted)
        }
        .padding(BsSpacing.md - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BsColor.brandAzure.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
    }

    // MARK: - Small building blocks

    private func fieldLabel(_ text: String, required: Bool) -> some View {
        HStack(spacing: 2) {
            Text(text)
                .font(BsTypography.inter(11, weight: "Bold"))
                .foregroundColor(BsColor.inkMuted)
                .textCase(.uppercase)
            if required {
                Text("*")
                    .font(BsTypography.inter(11, weight: "Bold"))
                    .foregroundColor(BsColor.danger)
            }
        }
    }

    private func pickerPill(label: String) -> some View {
        HStack(spacing: BsSpacing.xs) {
            Text(label)
                .font(BsTypography.inter(14, weight: "SemiBold"))
                .foregroundColor(BsColor.brandAzure)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(BsColor.brandAzure)
        }
        .padding(.horizontal, BsSpacing.md)
        .padding(.vertical, 10)
        .background(BsColor.brandAzure.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: - Submit

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            do {
                if let existing = existing {
                    // Rebuild the updated objective from form state, keeping
                    // all non-editable fields (id, status, progress, owner,
                    // assignee, created_at, KRs) as they were.
                    let updated = existing.withEdits(
                        title: trimmedTitle,
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    try await viewModel.updateObjective(updated)
                } else {
                    _ = try await viewModel.createObjective(
                        title: trimmedTitle,
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                        ownerId: nil,
                        period: period
                    )
                }
                onDismiss()
            } catch {
                errorMessage = ErrorLocalizer.localize(error)
            }
        }
    }
}

// MARK: - Objective edit helper

private extension Objective {
    /// Build a new `Objective` carrying the edit-surface fields overridden
    /// while preserving every other DB-backed property. Used by the edit
    /// path so we can round-trip through the model without a ton of
    /// ad-hoc inits.
    func withEdits(title: String, description: String) -> Objective {
        // Encode → mutate dictionary → decode avoids writing a memberwise
        // init that would need to be kept in sync with Objective's init.
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard
            let data = try? encoder.encode(self),
            var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return self
        }
        dict["title"] = title
        dict["description"] = description.isEmpty ? NSNull() : description
        guard
            let mutated = try? JSONSerialization.data(withJSONObject: dict),
            let result = try? decoder.decode(Objective.self, from: mutated)
        else {
            return self
        }
        return result
    }
}
