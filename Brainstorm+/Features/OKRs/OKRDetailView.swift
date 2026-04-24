import SwiftUI
import Supabase

/// Read-only detail view for a single objective. Web doesn't have a
/// dedicated detail route; this surfaces the same fields that Web's
/// expanded accordion row reveals (title, description, status, assignee,
/// owner, KR list with progress, computed objective progress).
public struct OKRDetailView: View {
    @StateObject private var viewModel: OKRDetailViewModel
    // Shared mutation VM — wraps the same client and runs the 4 mutations.
    // Period is irrelevant for these mutations; after each success we also
    // call `viewModel.load()` to refresh the single-objective state.
    @StateObject private var mutator: OKRListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pendingStatus: Objective.ObjectiveStatus? = nil
    @State private var pendingDeleteObjective: Bool = false
    @State private var pendingDeleteKr: KeyResult? = nil
    @State private var editingKr: KeyResult? = nil
    @State private var actionError: String? = nil

    public init(viewModel: OKRDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _mutator = StateObject(
            wrappedValue: OKRListViewModel(client: viewModel.supabaseClient)
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BsSpacing.lg) {
                headerCard
                progressCard
                ownerCard
                keyResultsCard
                if let msg = viewModel.errorMessage {
                    Text(msg)
                        .font(.system(.caption))
                        .foregroundColor(BsColor.danger)
                }
                Spacer(minLength: BsSpacing.xl)
            }
            .padding(.horizontal, BsSpacing.lg + 4)
            .padding(.top, BsSpacing.md)
        }
        .background(BsColor.surfaceSecondary.ignoresSafeArea())
        .navigationTitle("目标详情")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load()
        }
        .confirmationDialog(
            pendingStatus.map { "确认\(statusActionLabel($0))？" } ?? "",
            isPresented: Binding(
                get: { pendingStatus != nil },
                set: { if !$0 { pendingStatus = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingStatus
        ) { target in
            Button(statusActionLabel(target)) {
                performStatusChange(target)
                pendingStatus = nil
            }
            Button("取消", role: .cancel) { pendingStatus = nil }
        }
        .confirmationDialog(
            "删除目标",
            isPresented: $pendingDeleteObjective,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                performDeleteObjective()
                pendingDeleteObjective = false
            }
            Button("取消", role: .cancel) { pendingDeleteObjective = false }
        } message: {
            Text("删除后该目标及其 KR 无法恢复，确认？")
        }
        .confirmationDialog(
            "删除关键结果",
            isPresented: Binding(
                get: { pendingDeleteKr != nil },
                set: { if !$0 { pendingDeleteKr = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteKr
        ) { kr in
            Button("删除", role: .destructive) {
                performDeleteKr(kr)
                pendingDeleteKr = nil
            }
            Button("取消", role: .cancel) { pendingDeleteKr = nil }
        } message: { _ in
            Text("删除后该 KR 无法恢复，确认？")
        }
        .sheet(item: $editingKr) { kr in
            KeyResultMetaEditSheet(
                keyResult: kr,
                isLocked: viewModel.objective.status == .completed,
                onSave: { title, target, unit in
                    await performUpdateMeta(
                        kr: kr,
                        title: title,
                        target: target,
                        unit: unit
                    )
                },
                onDismiss: { editingKr = nil }
            )
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("好", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Mutation handlers

    private func statusActionLabel(_ target: Objective.ObjectiveStatus) -> String {
        switch target {
        case .active: return "启用"
        case .completed: return "标记为已完成"
        case .cancelled: return "取消目标"
        case .draft: return "重开为草稿"
        }
    }

    private func statusActionIcon(_ target: Objective.ObjectiveStatus) -> String {
        switch target {
        case .active: return "play.fill"
        case .completed: return "checkmark.seal.fill"
        case .cancelled: return "xmark.circle.fill"
        case .draft: return "arrow.uturn.backward"
        }
    }

    private func performStatusChange(_ target: Objective.ObjectiveStatus) {
        Task { @MainActor in
            do {
                try await mutator.updateObjectiveStatus(
                    objectiveId: viewModel.objective.id,
                    newStatus: target
                )
                await viewModel.load()
                Haptic.soft()
            } catch {
                Haptic.warning()
                actionError = ErrorLocalizer.localize(error)
            }
        }
    }

    private func performDeleteObjective() {
        Task { @MainActor in
            do {
                try await mutator.deleteObjective(objectiveId: viewModel.objective.id)
                Haptic.rigid()
                dismiss()
            } catch {
                Haptic.warning()
                actionError = ErrorLocalizer.localize(error)
            }
        }
    }

    private func performDeleteKr(_ kr: KeyResult) {
        Task { @MainActor in
            do {
                try await mutator.deleteKeyResult(keyResultId: kr.id)
                await viewModel.load()
                Haptic.rigid()
            } catch {
                Haptic.warning()
                actionError = ErrorLocalizer.localize(error)
            }
        }
    }

    private func performUpdateMeta(
        kr: KeyResult,
        title: String?,
        target: Double?,
        unit: String?
    ) async {
        do {
            try await mutator.updateKeyResultMeta(
                keyResultId: kr.id,
                title: title,
                targetValue: target,
                unit: unit
            )
            await viewModel.load()
            Haptic.soft()
            editingKr = nil
        } catch {
            Haptic.warning()
            actionError = ErrorLocalizer.localize(error)
        }
    }

    // MARK: - Header (title + status + period)

    private var headerCard: some View {
        let obj = viewModel.objective
        return VStack(alignment: .leading, spacing: BsSpacing.md - 2) {
            HStack(spacing: BsSpacing.sm) {
                Image(systemName: "target")
                    .font(.system(.callout, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(
                            colors: [BsColor.brandAzure, BsColor.brandMint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(obj.title)
                        .font(BsTypography.sectionTitle.weight(.bold))
                        .foregroundColor(BsColor.ink)
                    HStack(spacing: 6) {
                        statusBadge(obj.status)
                        if let period = obj.period {
                            Text(period)
                                .font(BsTypography.meta)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BsColor.brandAzure.opacity(0.08))
                                .foregroundColor(BsColor.brandAzure)
                                .clipShape(RoundedRectangle(cornerRadius: BsRadius.xs))
                        }
                    }
                }
                Spacer()
                objectiveMoreMenu
            }
            if let desc = obj.description, !desc.isEmpty {
                Divider().background(BsColor.borderSubtle)
                Text(desc)
                    .font(BsTypography.bodySmall)
                    .foregroundColor(BsColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BsSpacing.lg)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Progress

    private var progressCard: some View {
        let pct = viewModel.objective.computedProgress
        return VStack(alignment: .leading, spacing: BsSpacing.md - 2) {
            HStack {
                Text("进度")
                    .font(BsTypography.label)
                    .foregroundColor(BsColor.inkMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("\(pct)%")
                    .font(BsTypography.sectionTitle.weight(.bold))
                    .foregroundColor(progressColor(pct))
            }
            progressBar(progress: pct, height: 10)
            Text(progressNote(pct))
                .font(BsTypography.captionSmall)
                .foregroundColor(BsColor.inkMuted)
        }
        .padding(BsSpacing.lg)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    private func progressNote(_ pct: Int) -> String {
        let krs = viewModel.objective.keyResults ?? []
        let count = krs.count
        if count == 0 { return "尚未添加关键结果" }
        return "基于 \(count) 个关键结果的平均进度"
    }

    // MARK: - Owner + Assignee

    private var ownerCard: some View {
        VStack(alignment: .leading, spacing: BsSpacing.md - 2) {
            Text("负责人")
                .font(BsTypography.label)
                .foregroundColor(BsColor.inkMuted)
                .textCase(.uppercase)

            if viewModel.owner == nil && viewModel.assignee == nil {
                Text("未指定")
                    .font(.system(.caption))
                    .foregroundColor(BsColor.inkMuted)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let owner = viewModel.owner {
                        personRow(label: "Owner", profile: owner)
                    }
                    if let assignee = viewModel.assignee,
                       assignee.id != viewModel.owner?.id {
                        personRow(label: "负责执行", profile: assignee)
                    }
                }
            }
        }
        .padding(BsSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    private func personRow(label: String, profile: Profile) -> some View {
        HStack(spacing: BsSpacing.md - 2) {
            Circle()
                .fill(BsColor.brandAzure.opacity(0.15))
                .overlay(
                    Text(String((profile.fullName ?? profile.displayName ?? "?").prefix(1)))
                        .font(BsTypography.caption.weight(.bold))
                        .foregroundColor(BsColor.brandAzure)
                )
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.fullName ?? profile.displayName ?? "未命名")
                    .font(BsTypography.bodySmall.weight(.semibold))
                    .foregroundColor(BsColor.ink)
                Text(label)
                    .font(.system(.caption2))
                    .foregroundColor(BsColor.inkMuted)
            }
            Spacer()
            if let dept = profile.department, !dept.isEmpty {
                Text(dept)
                    .font(BsTypography.meta.weight(.medium))
                    .padding(.horizontal, BsSpacing.sm)
                    .padding(.vertical, 3)
                    .background(BsColor.brandMint.opacity(0.15))
                    .foregroundColor(BsColor.inkMuted)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Key Results

    private var keyResultsCard: some View {
        let krs = viewModel.objective.keyResults ?? []
        return VStack(alignment: .leading, spacing: BsSpacing.md) {
            HStack {
                Text("关键结果")
                    .font(BsTypography.label)
                    .foregroundColor(BsColor.inkMuted)
                    .textCase(.uppercase)
                Spacer()
                Text("共 \(krs.count) 项")
                    .font(BsTypography.label)
                    .foregroundColor(BsColor.inkMuted)
            }

            if krs.isEmpty {
                Text("暂无关键结果")
                    .font(.system(.caption))
                    .foregroundColor(BsColor.inkMuted)
            } else {
                VStack(spacing: BsSpacing.md - 2) {
                    ForEach(krs) { kr in
                        krDetailRow(kr)
                    }
                }
            }
        }
        .padding(BsSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    private var objectiveMoreMenu: some View {
        let transitions = OKRListViewModel.validStatusTransitions[viewModel.objective.status] ?? []
        return Menu {
            ForEach(transitions, id: \.self) { target in
                Button {
                    Haptic.selection()
                    pendingStatus = target
                } label: {
                    Label(statusActionLabel(target), systemImage: statusActionIcon(target))
                }
            }
            if !transitions.isEmpty {
                Divider()
            }
            Button(role: .destructive) {
                Haptic.selection()
                pendingDeleteObjective = true
            } label: {
                Label("删除目标", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(.title3, weight: .semibold))
                .foregroundColor(BsColor.brandAzure)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel("目标操作")
    }

    private func krDetailRow(_ kr: KeyResult) -> some View {
        let pct = kr.progressPercent
        let isLocked = viewModel.objective.status == .completed
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kr.title)
                    .font(BsTypography.bodySmall.weight(.semibold))
                    .foregroundColor(BsColor.ink)
                Spacer()
                Text("\(pct)%")
                    .font(BsTypography.bodySmall.weight(.bold))
                    .foregroundColor(progressColor(pct))
            }
            progressBar(progress: pct, height: 6)
            HStack {
                Text("当前 \(formatNumeric(kr.currentValue))\(kr.unit.map { " \($0)" } ?? "")")
                    .font(BsTypography.meta.weight(.medium))
                    .foregroundColor(BsColor.inkMuted)
                Spacer()
                Text("目标 \(formatNumeric(kr.targetValue))\(kr.unit.map { " \($0)" } ?? "")")
                    .font(BsTypography.meta.weight(.medium))
                    .foregroundColor(BsColor.inkMuted)
            }
        }
        .padding(BsSpacing.md)
        .background(BsColor.surfaceSecondary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
        .opacity(isLocked ? 0.7 : 1.0)
        .contextMenu {
            Button {
                Haptic.selection()
                editingKr = kr
            } label: {
                Label("编辑 KR 信息", systemImage: "pencil")
            }
            .disabled(isLocked)

            Button(role: .destructive) {
                Haptic.selection()
                pendingDeleteKr = kr
            } label: {
                Label("删除 KR", systemImage: "trash")
            }
        }
    }

    // MARK: - Formatting + shared helpers (duplicated from OKRListView
    //         intentionally — keeps each view self-contained; refactor
    //         to a shared OKRStyle helper when a third view needs them.)

    private func formatNumeric(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(v))
        }
        return String(format: "%.1f", v)
    }

    private func statusBadge(_ status: Objective.ObjectiveStatus) -> some View {
        let (bg, fg) = statusColors(status)
        return Text(status.displayLabel)
            .font(BsTypography.meta)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(fg)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.xs))
    }

    private func statusColors(_ status: Objective.ObjectiveStatus) -> (Color, Color) {
        switch status {
        case .draft:
            return (BsColor.inkFaint.opacity(0.2), BsColor.inkMuted)
        case .active:
            return (BsColor.brandAzure.opacity(0.1), BsColor.brandAzure)
        case .completed:
            return (BsColor.success.opacity(0.1), BsColor.success)
        case .cancelled:
            return (BsColor.danger.opacity(0.1), BsColor.danger)
        }
    }

    private func progressBar(progress: Int, height: CGFloat) -> some View {
        let clamped = max(0, min(progress, 100))
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BsColor.inkFaint.opacity(0.25))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: progressGradient(progress: clamped),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * CGFloat(clamped) / 100)
            }
        }
        .frame(height: height)
    }

    private func progressColor(_ p: Int) -> Color {
        if p >= 70 { return BsColor.success }
        if p >= 40 { return BsColor.warning }
        return BsColor.brandAzure
    }

    private func progressGradient(progress p: Int) -> [Color] {
        if p >= 70 {
            return [BsColor.success.opacity(0.85), BsColor.success]
        }
        if p >= 40 {
            return [BsColor.warning.opacity(0.85), BsColor.warning]
        }
        return [BsColor.brandAzure.opacity(0.85), BsColor.brandAzure]
    }
}

// MARK: - Key Result meta edit sheet
//
// Edits `title` / `target_value` / `unit` for a single KR. Validation
// mirrors Web `updateKeyResultMeta` (okr.ts:321-373):
//   • title 非空
//   • target_value > 0
//   • target_value ≥ current_value（阻止拉低目标至已有进度以下）
//
// The parent enforces the "objective completed" lock by not offering
// the "编辑 KR 信息" action when `isLocked`; we also disable the Save
// button if the sheet somehow opens in that state.
private struct KeyResultMetaEditSheet: View {
    let keyResult: KeyResult
    let isLocked: Bool
    let onSave: (_ title: String?, _ target: Double?, _ unit: String?) async -> Void
    let onDismiss: () -> Void

    @State private var title: String
    @State private var targetValue: Double
    @State private var unit: String
    @State private var isSubmitting: Bool = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, unit }

    init(
        keyResult: KeyResult,
        isLocked: Bool,
        onSave: @escaping (_ title: String?, _ target: Double?, _ unit: String?) async -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.keyResult = keyResult
        self.isLocked = isLocked
        self.onSave = onSave
        self.onDismiss = onDismiss
        _title = State(initialValue: keyResult.title)
        _targetValue = State(initialValue: keyResult.targetValue)
        _unit = State(initialValue: keyResult.unit ?? "")
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !isLocked
            && !isSubmitting
            && !trimmedTitle.isEmpty
            && targetValue > 0
            && targetValue >= keyResult.currentValue
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BsColor.surfaceSecondary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BsSpacing.lg) {
                        if isLocked {
                            lockedBanner
                        }
                        titleField
                        targetField
                        unitField

                        BsPrimaryButton(
                            "保存",
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
            .navigationTitle("编辑 KR 信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { onDismiss() }
                        .tint(BsColor.inkMuted)
                }
            }
            .onAppear { focus = .title }
        }
    }

    private var lockedBanner: some View {
        HStack(spacing: BsSpacing.sm) {
            Image(systemName: "lock.fill")
                .foregroundColor(BsColor.warning)
            Text("目标已标记为已完成，KR 无法编辑。")
                .font(BsTypography.captionSmall)
                .foregroundColor(BsColor.inkMuted)
        }
        .padding(BsSpacing.md - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BsColor.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            fieldLabel("KR 名称", required: true)
            TextField("如：提升客户满意度 90%", text: $title)
                .focused($focus, equals: .title)
                .textFieldStyle(.plain)
                .font(BsTypography.body)
                .foregroundColor(BsColor.ink)
                .padding(BsSpacing.md)
                .background(BsColor.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .stroke(BsColor.borderSubtle, lineWidth: 0.5)
                )
                .disabled(isLocked)
        }
    }

    private var targetField: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            fieldLabel("目标值", required: true)
            HStack(spacing: BsSpacing.md) {
                Text(formatNumeric(targetValue))
                    .font(BsTypography.body.weight(.semibold))
                    .foregroundColor(BsColor.ink)
                    .frame(minWidth: 48, alignment: .leading)
                Stepper(
                    "目标值",
                    value: $targetValue,
                    in: max(keyResult.currentValue, 1)...1_000_000,
                    step: stepSize()
                )
                .labelsHidden()
                .disabled(isLocked)
            }
            .padding(BsSpacing.md)
            .background(BsColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
            )
            Text("当前进度 \(formatNumeric(keyResult.currentValue))，目标值不能低于当前进度。")
                .font(BsTypography.meta)
                .foregroundColor(BsColor.inkMuted)
        }
    }

    private var unitField: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            fieldLabel("单位", required: false)
            TextField("如：% / 分 / 人", text: $unit)
                .focused($focus, equals: .unit)
                .textFieldStyle(.plain)
                .font(BsTypography.body)
                .foregroundColor(BsColor.ink)
                .padding(BsSpacing.md)
                .background(BsColor.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .stroke(BsColor.borderSubtle, lineWidth: 0.5)
                )
                .disabled(isLocked)
        }
    }

    private func fieldLabel(_ text: String, required: Bool) -> some View {
        HStack(spacing: 2) {
            Text(text)
                .font(BsTypography.label)
                .foregroundColor(BsColor.inkMuted)
                .textCase(.uppercase)
            if required {
                Text("*")
                    .font(BsTypography.label)
                    .foregroundColor(BsColor.danger)
            }
        }
    }

    /// Use 1 as the step for integer-looking targets; 0.5 for fractional.
    private func stepSize() -> Double {
        keyResult.targetValue.truncatingRemainder(dividingBy: 1) == 0 ? 1 : 0.5
    }

    private func formatNumeric(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(v)) }
        return String(format: "%.1f", v)
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            // Only send fields the user actually changed — mirrors Web's
            // partial update semantics (okr.ts:344-365).
            let newTitle: String? = trimmedTitle != keyResult.title ? trimmedTitle : nil
            let newTarget: Double? = targetValue != keyResult.targetValue ? targetValue : nil
            let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let originalUnit = keyResult.unit ?? ""
            let newUnit: String? = trimmedUnit != originalUnit ? trimmedUnit : nil

            // If nothing changed, just dismiss cleanly.
            if newTitle == nil && newTarget == nil && newUnit == nil {
                onDismiss()
                return
            }

            await onSave(newTitle, newTarget, newUnit)
        }
    }
}
