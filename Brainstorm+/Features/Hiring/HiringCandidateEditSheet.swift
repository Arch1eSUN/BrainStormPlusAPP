import SwiftUI
import UniformTypeIdentifiers
import PDFKit

public struct HiringCandidateEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let existing: Candidate?
    private let positions: [JobPosition]
    private let onSaved: () -> Void

    @State private var fullName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var positionId: UUID?
    @State private var resumeText: String = ""
    @State private var resumeUrl: String = ""
    @State private var notes: String = ""
    @State private var status: Candidate.CandidateStatus = .new

    @State private var showFileImporter: Bool = false
    @State private var isParsingResume: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    public init(
        existing: Candidate?,
        positions: [JobPosition],
        onSaved: @escaping () -> Void
    ) {
        self.existing = existing
        self.positions = positions
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("姓名", text: $fullName)
                        .textInputAutocapitalization(.words)
                    TextField("邮箱", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("电话", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section("应聘岗位") {
                    Picker("岗位", selection: $positionId) {
                        Text("不指定").tag(UUID?.none)
                        ForEach(positions) { p in
                            Text(p.title).tag(Optional(p.id))
                        }
                    }
                }

                if existing != nil {
                    Section("跟进状态") {
                        Picker("状态", selection: $status) {
                            ForEach(Candidate.CandidateStatus.allCases, id: \.self) { s in
                                Text(s.displayLabel).tag(s)
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label(isParsingResume ? "解析中…" : "上传 PDF 自动解析", systemImage: "doc.text.viewfinder")
                        }
                        .disabled(isParsingResume)
                        Spacer()
                    }
                    TextField("简历正文（粘贴或通过上传解析）", text: $resumeText, axis: .vertical)
                        .lineLimit(4...12)
                } header: {
                    Text("简历内容")
                } footer: {
                    Text("PDF 将在本机通过 PDFKit 抽取可检索文本。扫描件如无 OCR 层可能解析为空。")
                        .font(.caption2)
                }

                Section("简历附件 URL（可选）") {
                    TextField("https://…", text: $resumeUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("备注") {
                    TextField("跟进备注", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(existing == nil ? "添加候选人" : "编辑候选人")
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
                    .disabled(isSaving || trimmedName.isEmpty)
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
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                Task { await ingestPDF(result) }
            }
            .zyErrorBanner($errorMessage)
            .onAppear { hydrate() }
        }
    }

    private var trimmedName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hydrate() {
        guard let existing else { return }
        fullName = existing.fullName
        email = existing.email ?? ""
        phone = existing.phone ?? ""
        positionId = existing.positionId
        resumeText = existing.resumeText ?? ""
        resumeUrl = existing.resumeUrl ?? ""
        notes = existing.notes ?? ""
        status = existing.status
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if let existing {
                try await HiringRepository.shared.updateCandidate(
                    id: existing.id,
                    fullName: fullName,
                    email: email,
                    phone: phone,
                    positionId: positionId,
                    resumeText: resumeText,
                    resumeUrl: resumeUrl,
                    notes: notes,
                    status: status
                )
            } else {
                try await HiringRepository.shared.createCandidate(
                    fullName: fullName,
                    email: email,
                    phone: phone,
                    positionId: positionId,
                    resumeText: resumeText,
                    resumeUrl: resumeUrl,
                    notes: notes
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = ErrorLocalizer.localize(error)
        }
    }

    private func ingestPDF(_ result: Result<[URL], Error>) async {
        isParsingResume = true
        defer { isParsingResume = false }
        switch result {
        case .failure(let err):
            errorMessage = "选择文件失败：\(err.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let doc = PDFDocument(url: url), let text = doc.string {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    errorMessage = "PDF 未包含可抽取文本（可能是扫描件）"
                } else {
                    resumeText = trimmed
                }
            } else {
                errorMessage = "无法读取该 PDF 文件"
            }
        }
    }
}
