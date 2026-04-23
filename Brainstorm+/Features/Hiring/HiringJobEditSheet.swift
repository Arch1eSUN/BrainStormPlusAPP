import SwiftUI

public struct HiringJobEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let existing: JobPosition?
    private let onSaved: () -> Void

    @State private var title: String = ""
    @State private var department: String = ""
    @State private var salaryRange: String = ""
    @State private var description: String = ""
    @State private var requirements: String = ""
    @State private var employmentType: JobPosition.EmploymentType = .fullTime
    @State private var status: JobPosition.PositionStatus = .open

    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    public init(existing: JobPosition?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("岗位信息") {
                    TextField("岗位名称", text: $title)
                        .autocorrectionDisabled()
                    TextField("部门", text: $department)
                        .autocorrectionDisabled()
                    TextField("薪资范围（例如 15K-25K）", text: $salaryRange)
                        .autocorrectionDisabled()
                }

                Section("用工类型") {
                    Picker("用工类型", selection: $employmentType) {
                        ForEach(JobPosition.EmploymentType.allCases, id: \.self) { t in
                            Text(t.displayLabel).tag(t)
                        }
                    }
                }

                if existing != nil {
                    Section("招聘状态") {
                        Picker("状态", selection: $status) {
                            ForEach(JobPosition.PositionStatus.allCases, id: \.self) { s in
                                Text(s.displayLabel).tag(s)
                            }
                        }
                    }
                }

                Section("岗位描述") {
                    TextField("岗位职责", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("任职要求") {
                    TextField("学历/技能/经验要求", text: $requirements, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(existing == nil ? "新建岗位" : "编辑岗位")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving || trimmedTitle.isEmpty)
                }
            }
            .overlay {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView("保存中…")
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                    }
                }
            }
            .zyErrorBanner($errorMessage)
            .onAppear { hydrate() }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hydrate() {
        guard let existing else { return }
        title = existing.title
        department = existing.department ?? ""
        salaryRange = existing.salaryRange ?? ""
        description = existing.description ?? ""
        requirements = existing.requirements ?? ""
        employmentType = existing.employmentType
        status = existing.status
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if let existing {
                try await HiringRepository.shared.updateJobPosition(
                    id: existing.id,
                    title: title,
                    department: department,
                    description: description,
                    requirements: requirements,
                    salaryRange: salaryRange,
                    employmentType: employmentType,
                    status: status
                )
            } else {
                try await HiringRepository.shared.createJobPosition(
                    title: title,
                    department: department,
                    description: description,
                    requirements: requirements,
                    salaryRange: salaryRange,
                    employmentType: employmentType
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
        }
    }
}
