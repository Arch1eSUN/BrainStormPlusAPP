import SwiftUI

// ══════════════════════════════════════════════════════════════════
// PayrollEditSheet
// ──────────────────────────────────────────────────────────────────
// Finance-ops admin sheet for creating or editing a single
// `payroll_records` row (by `user_id` + `period`).
//
// Mirrors the write side of Web `payroll.ts adminSavePayroll`
// (line 142-182) — the mobile edition exposes the core 4 money fields
// (base_salary / bonus / deductions / net_pay-computed). Richer fields
// (paid_leave_days, fines, calculation_version) remain Web-only.
//
// Create path: pass `payroll: nil` and `userId`, the employee is
// chosen via the picker and `period` defaults to the current month.
//
// Edit path: pass the existing `payroll` — fields are pre-seeded and
// user/period are locked.
// ══════════════════════════════════════════════════════════════════

public struct PayrollEditSheet: View {
    @ObservedObject var viewModel: PayrollListViewModel
    /// When non-nil we're editing an existing row; when nil we're creating.
    public let payroll: PayrollRecord?

    public let onDismiss: () -> Void

    // MARK: - Form state

    @State private var selectedUserId: UUID?
    @State private var period: String
    @State private var baseSalaryText: String
    @State private var bonusText: String
    @State private var deductionsText: String

    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case base, bonus, deductions }

    public init(
        viewModel: PayrollListViewModel,
        payroll: PayrollRecord?,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.payroll = payroll
        self.onDismiss = onDismiss

        if let p = payroll {
            _selectedUserId = State(initialValue: p.userId)
            _period = State(initialValue: p.period)
            _baseSalaryText = State(initialValue: Self.decimalInputString(p.baseSalary))
            _bonusText = State(initialValue: Self.decimalInputString(p.bonus))
            _deductionsText = State(initialValue: Self.decimalInputString(p.deductions))
        } else {
            _selectedUserId = State(initialValue: nil)
            _period = State(initialValue: Self.currentPeriodString())
            _baseSalaryText = State(initialValue: "")
            _bonusText = State(initialValue: "")
            _deductionsText = State(initialValue: "")
        }
    }

    private var isEditing: Bool { payroll != nil }
    private var screenTitle: String { isEditing ? "编辑薪资" : "新建薪资" }

    // MARK: - Derived state

    private var parsedBase: Decimal? { Self.parseAmount(baseSalaryText) }
    private var parsedBonus: Decimal? { Self.parseAmount(bonusText) }
    private var parsedDeductions: Decimal? { Self.parseAmount(deductionsText) }

    private var computedNetPay: Decimal? {
        guard let b = parsedBase, let bo = parsedBonus, let d = parsedDeductions else {
            return nil
        }
        return b + bo - d
    }

    private var employeeDisplayName: String {
        if let id = selectedUserId,
           let match = viewModel.employeeDirectory.first(where: { $0.id == id }) {
            return match.fullName ?? id.uuidString
        }
        if isEditing, let id = selectedUserId {
            return id.uuidString
        }
        return "选择员工"
    }

    private var canSubmit: Bool {
        if isSubmitting { return false }
        guard selectedUserId != nil else { return false }
        guard !period.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // All three money fields must parse as non-negative decimals.
        guard let b = parsedBase, b >= 0 else { return false }
        guard let bo = parsedBonus, bo >= 0 else { return false }
        guard let d = parsedDeductions, d >= 0 else { return false }
        return true
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                BsColor.surfaceSecondary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: BsSpacing.lg) {
                        headerCard

                        employeeField
                        periodField

                        amountField(
                            label: "基础薪资",
                            text: $baseSalaryText,
                            field: .base,
                            placeholder: "0.00"
                        )
                        amountField(
                            label: "奖金",
                            text: $bonusText,
                            field: .bonus,
                            placeholder: "0.00"
                        )
                        amountField(
                            label: "扣款",
                            text: $deductionsText,
                            field: .deductions,
                            placeholder: "0.00"
                        )

                        netPayPreview

                        BsPrimaryButton(
                            isEditing ? "保存修改" : "创建",
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
                    Button("取消") { onDismiss() }
                        .tint(BsColor.inkMuted)
                }
            }
            .task {
                // Load the employee directory once on open so the picker
                // has names to show. Edit path also benefits — we use the
                // directory to render the locked employee's full name.
                if viewModel.employeeDirectory.isEmpty {
                    await viewModel.loadEmployeeDirectory()
                }
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

    // MARK: - Sections

    private var headerCard: some View {
        HStack(alignment: .center, spacing: BsSpacing.sm) {
            Image(systemName: isEditing ? "pencil.line" : "yensign.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(BsColor.brandAzure)
            VStack(alignment: .leading, spacing: 2) {
                Text(screenTitle)
                    .font(BsTypography.cardTitle)
                    .foregroundStyle(BsColor.ink)
                Text(isEditing
                    ? "修改该员工在所选期间的薪资构成"
                    : "为员工登记所选期间的薪资")
                    .font(BsTypography.captionSmall)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer()
        }
        .padding(BsSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BsColor.brandAzure.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
    }

    private var employeeField: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            fieldLabel("员工", required: true)

            if isEditing {
                // Edit path: employee is locked (identity is part of the
                // onConflict key — can't mutate).
                HStack {
                    Text(employeeDisplayName)
                        .font(BsTypography.body)
                        .foregroundStyle(BsColor.ink)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
                .padding(BsSpacing.md)
                .background(BsColor.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .stroke(BsColor.borderSubtle, lineWidth: 0.5)
                )
            } else {
                Menu {
                    if viewModel.isLoadingDirectory {
                        Text("加载中…")
                    } else if viewModel.employeeDirectory.isEmpty {
                        Text("暂无在职员工")
                    } else {
                        ForEach(viewModel.employeeDirectory) { entry in
                            Button(entry.fullName ?? entry.id.uuidString) {
                                selectedUserId = entry.id
                                // Haptic removed: menu 选项过密震动
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(employeeDisplayName)
                            .font(BsTypography.body)
                            .foregroundStyle(selectedUserId == nil ? BsColor.inkMuted : BsColor.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    .padding(BsSpacing.md)
                    .background(BsColor.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                            .stroke(BsColor.borderSubtle, lineWidth: 0.5)
                    )
                }
            }
        }
    }

    private var periodField: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            fieldLabel("周期 (yyyy-MM)", required: true)

            if isEditing {
                HStack {
                    Text(period)
                        .font(BsTypography.body)
                        .foregroundStyle(BsColor.ink)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(BsColor.inkMuted)
                }
                .padding(BsSpacing.md)
                .background(BsColor.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .stroke(BsColor.borderSubtle, lineWidth: 0.5)
                )
            } else {
                TextField("2026-04", text: $period)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(BsTypography.body)
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
    }

    private func amountField(
        label: String,
        text: Binding<String>,
        field: Field,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            fieldLabel(label, required: true)
            HStack(spacing: BsSpacing.xs) {
                Text("¥")
                    .font(BsTypography.body)
                    .foregroundStyle(BsColor.inkMuted)
                TextField(placeholder, text: text)
                    .focused($focusedField, equals: field)
                    .keyboardType(.decimalPad)
                    .font(BsTypography.body)
                    .foregroundColor(BsColor.ink)
            }
            .padding(BsSpacing.md)
            .background(BsColor.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .stroke(BsColor.borderSubtle, lineWidth: 0.5)
            )
        }
    }

    private var netPayPreview: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            fieldLabel("实发金额 (自动计算)", required: false)
            HStack {
                Text("¥")
                    .font(BsTypography.statLarge)
                    .foregroundStyle(BsColor.inkMuted)
                Text(computedNetPay.map(Self.formatCurrency) ?? "—")
                    .font(BsTypography.statLarge)
                    .foregroundStyle(BsColor.ink)
                Spacer()
            }
            .padding(BsSpacing.md)
            .background(BsColor.brandAzure.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))

            Text("= 基础薪资 + 奖金 − 扣款")
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
        }
    }

    // MARK: - Small building blocks

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

    // MARK: - Submit

    private func submit() {
        guard canSubmit,
              let userId = selectedUserId,
              let base = parsedBase,
              let bonus = parsedBonus,
              let deductions = parsedDeductions
        else { return }

        let input = PayrollListViewModel.AdminPayrollInput(
            userId: userId,
            period: period.trimmingCharacters(in: .whitespacesAndNewlines),
            baseSalary: base,
            bonus: bonus,
            deductions: deductions
        )

        isSubmitting = true
        Task { @MainActor in
            let ok = await viewModel.adminSavePayroll(record: input)
            isSubmitting = false
            if ok {
                Haptic.medium() // 保存薪资 mutation 成功
                onDismiss()
            } else {
                Haptic.warning()
                errorMessage = viewModel.errorMessage ?? "保存失败，请稍后重试"
            }
        }
    }

    // MARK: - Helpers

    private static func currentPeriodString() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM"
        return df.string(from: Date())
    }

    /// Convert a backing `Decimal` (from the DB) into the editable string
    /// — drops trailing zeros past 2 d.p. for a cleaner edit experience.
    private static func decimalInputString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ""
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }

    /// Parse a user-entered amount. Returns `nil` if empty, non-numeric,
    /// negative, or has more than 2 fractional digits.
    private static func parseAmount(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        // Reject anything that isn't digits-and-at-most-one-dot.
        let allowed = CharacterSet(charactersIn: "0123456789.")
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) { return nil }
        let dotCount = trimmed.filter { $0 == "." }.count
        if dotCount > 1 { return nil }
        if let dotIndex = trimmed.firstIndex(of: ".") {
            let fractional = trimmed.distance(from: dotIndex, to: trimmed.endIndex) - 1
            if fractional > 2 { return nil }
        }
        guard let decimal = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        if decimal < 0 { return nil }
        return decimal
    }

    /// Display helper — 2 fraction digits, grouped thousands.
    private static func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
}
