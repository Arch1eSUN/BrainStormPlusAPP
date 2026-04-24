import SwiftUI
import Combine
import PhotosUI
import UniformTypeIdentifiers

// ══════════════════════════════════════════════════════════════════
// Batch C.4c — Knowledge base list with CRUD + file-attachment port.
//
// 1:1 surface port of `BrainStorm+-Web/src/app/dashboard/knowledge/page.tsx`:
//   • list of knowledge cards (reads from VM)
//   • search field + category chip row
//   • admin-only "新建文档" + "上传文件" toolbar buttons
//   • per-row context menu (编辑 / 删除) + trailing swipe
//   • tap navigates to `KnowledgeDetailView` (markdown-rendered body)
//
// Admin gating uses the same predicate the Web page uses
// (`isAdminUser = hasPrimaryRoleLevel(primaryRole, 'admin')`) —
// resolved on iOS via `RBACManager.migrateLegacyRole` + the .admin /
// .superadmin cases, matching the ProjectListView gating.
//
// Out of scope (see VM notes): author avatar footer (the Web fetch
// joins into profiles; iOS VM doesn't yet). AI summary is wired —
// see `KnowledgeDetailView.aiSummarySection` + the bridge route at
// `/api/mobile/knowledge/ai-summary`.
// ══════════════════════════════════════════════════════════════════

public struct KnowledgeListView: View {
    @StateObject private var viewModel: KnowledgeListViewModel

    /// Identity source for admin gating — matches the pattern used by
    /// `ProjectListView`.
    @Environment(SessionManager.self) private var sessionManager

    // Edit / create sheet state.
    @State private var editTarget: KnowledgeEditTarget?

    // File-upload sheet + pickers.
    @State private var showUploadSheet: Bool = false
    @State private var uploadCategoryInput: String = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter: Bool = false

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(viewModel: KnowledgeListViewModel, isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.isEmbedded = isEmbedded
    }

    public var body: some View {
        if isEmbedded {
            coreContent
        } else {
            NavigationStack { coreContent }
        }
    }

    private var coreContent: some View {
        Group {
            if viewModel.isLoading && viewModel.articles.isEmpty {
                ProgressView()
            } else {
                content
            }
        }
        .navigationTitle("知识库")
        .toolbar {
            if isAdmin {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            editTarget = .new
                        } label: {
                            Label("新建文档", systemImage: "square.and.pencil")
                        }
                        Button {
                            showUploadSheet = true
                        } label: {
                            Label("上传文件", systemImage: "arrow.up.doc")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "搜索文档…")
        .onSubmit(of: .search) {
            Task { await viewModel.fetchArticles() }
        }
        // Match Web's `useEffect([search, catFilter])` — when the
        // user clears the query with the native `x` button there
        // is no `onSubmit`, so we also reload on empty-string
        // transitions and on every category filter change.
        .onChange(of: viewModel.searchText) { old, new in
            if old.isEmpty == false, new.isEmpty {
                Task { await viewModel.fetchArticles() }
            }
        }
        .onChange(of: viewModel.categoryFilter) { _, _ in
            Task { await viewModel.fetchArticles() }
        }
        .refreshable {
            await viewModel.fetchArticles()
        }
        .task {
            await viewModel.fetchArticles()
        }
        .sheet(item: $editTarget) { target in
            KnowledgeEditView(
                viewModel: viewModel,
                existingArticle: target.article
            )
        }
        .sheet(isPresented: $showUploadSheet) {
            uploadSheet
        }
        .fileImporter(
            isPresented: $showFileImporter,
            // Broad content-type list to mirror Web's
            // `FILE_ACCEPT` (pdf/doc/docx/pptx/pages/txt/md +
            // audio/video). Server-side RLS + the bucket's 100MB
            // cap are the real guardrails — the client picker is
            // a usability filter only.
            allowedContentTypes: [
                .pdf, .plainText, .rtf, .image, .movie, .audio, .item
            ],
            allowsMultipleSelection: false
        ) { result in
            Task { await handlePickedFiles(result) }
        }
        .onChange(of: photoItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task { await handlePhotoItems(newValue) }
            photoItems = []
        }
        .zyErrorBanner($viewModel.errorMessage)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: BsSpacing.lg) {
                // Category chip row — mirrors Web's chips above the grid.
                categoryChips

                if viewModel.articles.isEmpty {
                    ContentUnavailableView(
                        "暂无文档",
                        systemImage: "book.closed",
                        description: Text(searchOrCategoryActive
                            ? "没有匹配的文档"
                            : "创建你的第一篇知识文档")
                    )
                    .padding(.top, BsSpacing.xxl + 8)
                } else {
                    articleList
                }
            }
            .padding(.vertical)
        }
        .background(BsColor.pageBackground)
    }

    @ViewBuilder
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BsSpacing.sm) {
                chip(label: "全部", isSelected: viewModel.categoryFilter == nil) {
                    viewModel.categoryFilter = nil
                }
                ForEach(viewModel.categories, id: \.self) { c in
                    chip(label: c, isSelected: viewModel.categoryFilter == c) {
                        viewModel.categoryFilter = c
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(BsTypography.captionSmall)
                .padding(.horizontal, BsSpacing.md)
                .padding(.vertical, BsSpacing.xs + 2)
                .background(isSelected ? BsColor.brandAzure.opacity(0.15) : BsColor.surfaceSecondary)
                .foregroundStyle(isSelected ? BsColor.brandAzure : BsColor.ink)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var articleList: some View {
        LazyVStack(spacing: BsSpacing.md) {
            ForEach(viewModel.articles) { article in
                NavigationLink {
                    KnowledgeDetailView(
                        article: article,
                        viewModel: viewModel,
                        canEdit: isAdmin,
                        onEdit: isAdmin ? { editTarget = .edit(article) } : nil,
                        onDelete: isAdmin
                            ? { Task { await viewModel.deleteArticle(article) } }
                            : nil
                    )
                } label: {
                    KnowledgeCardView(article: article)
                        .padding(.horizontal)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if isAdmin {
                        Button("编辑") { editTarget = .edit(article) }
                        Button("删除", role: .destructive) {
                            Task { await viewModel.deleteArticle(article) }
                        }
                    }
                    if let urlString = article.fileUrl, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label("打开附件", systemImage: "paperclip")
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if isAdmin {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteArticle(article) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            editTarget = .edit(article)
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        .tint(BsColor.brandAzure)
                    }
                }
            }
        }
    }

    // MARK: - Upload sheet

    @ViewBuilder
    private var uploadSheet: some View {
        NavigationStack {
            Form {
                Section("分类") {
                    TextField("如：开发规范、入职指南", text: $uploadCategoryInput)
                }

                Section {
                    PhotosPicker(
                        selection: $photoItems,
                        maxSelectionCount: 1,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("从相册选择", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("选择文件", systemImage: "doc.badge.plus")
                    }
                } header: {
                    Text("选择文件")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("支持 PDF、Word、PPT、Pages、TXT、Markdown、音频、视频")
                        Text("单个文件最大 100MB")
                    }
                    .font(.caption2)
                }

                if viewModel.isUploading {
                    Section {
                        HStack(spacing: BsSpacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("上传中…")
                                .font(BsTypography.caption)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                    }
                }
            }
            .navigationTitle("上传知识文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showUploadSheet = false }
                }
            }
        }
    }

    // MARK: - Upload handlers

    private func handlePhotoItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            // PhotosPicker decodes HEIC → JPEG by default; extension
            // follows suit (matches ReimbursementSubmitViewModel).
            let fileName = "IMG_\(UUID().uuidString.prefix(8)).jpg"
            _ = await viewModel.uploadFile(
                data: data,
                fileName: fileName,
                mimeType: "image/jpeg",
                category: uploadCategoryInput
            )
        }
        closeUploadSheetIfDone()
    }

    private func handlePickedFiles(_ result: Result<[URL], Error>) async {
        let urls: [URL]
        switch result {
        case .success(let picked): urls = picked
        case .failure(let error):
            viewModel.errorMessage = "选择文件失败: \(ErrorLocalizer.localize(error))"
            return
        }
        guard !urls.isEmpty else { return }

        for url in urls {
            // Security-scoped resources need explicit start/stop — same
            // pattern used by ReimbursementSubmitViewModel.ingestPickedFiles.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else { continue }
            let fileName = url.lastPathComponent
            let mime = UTType(filenameExtension: url.pathExtension)?
                .preferredMIMEType ?? "application/octet-stream"
            _ = await viewModel.uploadFile(
                data: data,
                fileName: fileName,
                mimeType: mime,
                category: uploadCategoryInput
            )
        }
        closeUploadSheetIfDone()
    }

    private func closeUploadSheetIfDone() {
        if viewModel.errorMessage == nil {
            showUploadSheet = false
            uploadCategoryInput = ""
        }
    }

    // MARK: - Helpers

    private var isAdmin: Bool {
        let role = RBACManager.shared
            .migrateLegacyRole(sessionManager.currentProfile?.role)
            .primaryRole
        switch role {
        case .admin, .superadmin: return true
        case .employee: return false
        }
    }

    private var searchOrCategoryActive: Bool {
        !(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || (viewModel.categoryFilter?.isEmpty == false)
    }
}

// MARK: - Edit target

/// Identifiable wrapper so `.sheet(item:)` re-creates the sheet when
/// a different row is edited in quick succession. Matches the
/// `DailyLogKnowledgeEditTarget` pattern used by ReportingListView.
private enum KnowledgeEditTarget: Identifiable {
    case new
    case edit(KnowledgeArticle)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let a): return a.id.uuidString
        }
    }

    var article: KnowledgeArticle? {
        if case .edit(let a) = self { return a }
        return nil
    }
}
