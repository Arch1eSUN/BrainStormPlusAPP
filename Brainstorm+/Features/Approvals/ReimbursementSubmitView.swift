import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Supabase

// ══════════════════════════════════════════════════════════════════
// Sprint 4.4 — Reimbursement submit form.
//
// 1:1 port of `src/components/approval/reimbursement-form.tsx` +
// `src/components/approval/forms/receipt-uploader.tsx`.
//
// Money input: we use `TextField(value: $amountYuan, format: .number)`
// which binds a `Decimal` directly — avoids the `String → Double →
// round` dance that would let 19.99 get serialized as 19.990000004.
// The form shows yuan; the VM converts to cents on submit.
//
// Attachments + receipt URLs (Batch C.1): added a PhotosPicker + file
// importer UI. Uploads stream through `ApprovalStorageClient` to the
// `approval_attachments` bucket mirroring Web's path convention
// (`{userId}/{uuid}.{ext}`). Persisted URLs go onto the RPC's
// `p_receipt_urls` JSONB param, which the server stores on
// `approval_request_reimbursement.receipt_urls` as a `text[]` the
// detail view already decodes.
// ══════════════════════════════════════════════════════════════════

public struct ReimbursementSubmitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ReimbursementSubmitViewModel

    private let onSubmitted: (UUID) -> Void

    // Upload UI state. Kept in the view (not the VM) because the
    // PhotosPicker/fileImporter bindings are SwiftUI-framework-coupled
    // and the VM should stay `import UIKit`-free.
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter: Bool = false

    private static let selectablePriorities: [RequestPriority] = [
        .low, .medium, .high, .urgent
    ]

    public init(
        client: SupabaseClient,
        onSubmitted: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ReimbursementSubmitViewModel(client: client))
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                BsColor.pageBackground.ignoresSafeArea()
                Form {
                Section("报销项目") {
                    TextField("项目名称", text: $viewModel.itemDescription)

                    Picker("类别", selection: $viewModel.category) {
                        ForEach(ReimbursementCategory.allCases) { c in
                            Text(c.displayLabel).tag(c)
                        }
                    }

                    DatePicker(
                        "购买/发生日期",
                        selection: $viewModel.purchaseDate,
                        displayedComponents: .date
                    )
                }

                Section("金额") {
                    HStack {
                        TextField("金额", value: $viewModel.amountYuan, format: .number)
                            .keyboardType(.decimalPad)
                        Text(viewModel.currency.isEmpty ? "CNY" : viewModel.currency)
                            .foregroundStyle(.secondary)
                    }
                    TextField("币种 (默认 CNY)", text: $viewModel.currency)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }

                Section("商户与支付") {
                    TextField("商户/收款方", text: $viewModel.merchant)

                    Picker("支付方式", selection: $viewModel.paymentMethod) {
                        ForEach(PaymentMethod.allCases) { m in
                            Text(m.displayLabel).tag(m)
                        }
                    }
                }

                Section("用途说明") {
                    TextField(
                        "请说明该笔费用的用途",
                        text: $viewModel.purpose,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }

                Section("附加信息") {
                    TextField(
                        "业务事由（可选）",
                        text: $viewModel.businessReason,
                        axis: .vertical
                    )
                    .lineLimit(2...4)

                    TextField("关联项目（可选）", text: $viewModel.relatedProject)
                }

                Section {
                    receiptUploader
                } header: {
                    Text("票据附件")
                } footer: {
                    Text("支持 JPG / PNG / PDF。上传后可长按删除。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("优先级") {
                    Picker("优先级", selection: $viewModel.priority) {
                        ForEach(Self.selectablePriorities, id: \.self) { p in
                            Text(priorityLabel(p)).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("报销申请")
            .navigationBarTitleDisplayMode(.inline)
            .zyErrorBanner($viewModel.errorMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        Haptic.light()
                        dismiss()
                    }
                    .disabled(viewModel.isSubmitting || viewModel.isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") {
                        Haptic.medium()
                        Task { await handleSubmit() }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .bsLoadingOverlay(isLoading: viewModel.isSubmitting, label: "提交中…")
            .onChange(of: viewModel.category) { _, _ in Haptic.selection() }
            .onChange(of: viewModel.paymentMethod) { _, _ in Haptic.selection() }
            .onChange(of: viewModel.priority) { _, _ in Haptic.selection() }
            .onChange(of: photoItems) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task { await viewModel.ingestPhotoItems(newValue) }
                photoItems = []
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: true
            ) { result in
                Task { await viewModel.ingestPickedFiles(result) }
            }
        }
    }

    // MARK: - Receipt uploader

    @ViewBuilder
    private var receiptUploader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                        .foregroundStyle(Color.accentColor)
                }

                Button {
                    showFileImporter = true
                } label: {
                    Label("选择文件", systemImage: "doc.badge.plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                if viewModel.isUploading {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("上传中…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !viewModel.receiptUrls.isEmpty {
                receiptGrid
            } else {
                Text("尚未上传任何票据")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var receiptGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 80), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(Array(viewModel.receiptUrls.enumerated()), id: \.offset) { idx, url in
                receiptTile(urlString: url, index: idx)
            }
        }
    }

    @ViewBuilder
    private func receiptTile(urlString: String, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let url = URL(string: urlString), Self.isImageURL(urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().controlSize(.small)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fileTile(label: "图像")
                    @unknown default:
                        fileTile(label: "图像")
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                fileTile(label: "PDF")
                    .frame(width: 80, height: 80)
            }

            // Delete overlay — long-press avoids accidental tap-removal
            // in a compact grid, mirroring the hover-on-desktop Web UI.
            Button(role: .destructive) {
                Haptic.rigid()
                viewModel.removeReceipt(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white, Color.red)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .accessibilityLabel("删除附件 \(index + 1)")
        }
    }

    @ViewBuilder
    private func fileTile(label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 80, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private static func isImageURL(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.hasSuffix(".jpg")
            || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".png")
            || lower.hasSuffix(".gif")
            || lower.hasSuffix(".webp")
            || lower.hasSuffix(".heic")
            || lower.hasSuffix(".heif")
    }

    // MARK: - Helpers

    private func priorityLabel(_ p: RequestPriority) -> String {
        switch p {
        case .low:     return "低"
        case .medium:  return "中"
        case .high:    return "高"
        case .urgent:  return "紧急"
        case .unknown: return "未知"
        }
    }

    private func handleSubmit() async {
        let ok = await viewModel.submit()
        if ok, let id = viewModel.createdRequestId {
            Haptic.success()
            onSubmitted(id)
            dismiss()
        } else {
            Haptic.error()
        }
    }

}

#Preview {
    ReimbursementSubmitView(client: supabase) { _ in }
}
