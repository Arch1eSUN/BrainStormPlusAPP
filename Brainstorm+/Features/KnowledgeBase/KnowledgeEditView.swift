import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Batch C.4c — Create/edit sheet for a knowledge article.
//
// 1:1 surface port of the two dialogs in
// `BrainStorm+-Web/src/app/dashboard/knowledge/page.tsx` (Dialog
// "新建知识文档" + Dialog "编辑知识文档"). Fields: title / category /
// content. Web uses a plain `<textarea>` for content with a Markdown
// placeholder — iOS uses `TextEditor` to stay on the stdlib per the
// batch brief.
//
// Not ported:
//   • File-attachment UI here — attaching a file creates a new row
//     via the list toolbar's file picker rather than re-uploading
//     inside an edit form (Web separates the two too; the edit
//     dialog only touches title/content/category).
//   • Tags input — the Web schema has a `tags` column but page.tsx
//     never surfaces a picker; the textarea is the only body input.
// ══════════════════════════════════════════════════════════════════

public struct KnowledgeEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var viewModel: KnowledgeListViewModel

    private let existingArticle: KnowledgeArticle?

    @State private var title: String
    @State private var category: String
    @State private var content: String
    @State private var showDeleteConfirm = false

    public init(viewModel: KnowledgeListViewModel, existingArticle: KnowledgeArticle? = nil) {
        self.viewModel = viewModel
        self.existingArticle = existingArticle
        _title = State(initialValue: existingArticle?.title ?? "")
        _category = State(initialValue: existingArticle?.category ?? "")
        _content = State(initialValue: existingArticle?.content ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("文档标题", text: $title)
                }

                Section("分类") {
                    TextField("如：开发规范、入职指南", text: $category)
                }

                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 220)
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("支持 Markdown 格式…")
                            .font(.caption)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                } header: {
                    Text("内容")
                } footer: {
                    if existingArticle?.fileUrl != nil {
                        Text("此文档附带一个文件；编辑仅更新标题、分类与内容，附件保持不变。")
                            .font(.caption2)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }

                if existingArticle != nil {
                    Section {
                        Button("删除文档", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(existingArticle == nil ? "新建文档" : "编辑文档")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text(existingArticle == nil ? "发布" : "保存")
                    }
                    .disabled(isSaveDisabled)
                }
            }
            .overlay {
                if viewModel.isSaving {
                    ProgressView().controlSize(.large)
                }
            }
            .confirmationDialog(
                "确定删除这篇知识文档吗？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    Task {
                        if let article = existingArticle {
                            await viewModel.deleteArticle(article)
                            if viewModel.errorMessage == nil { dismiss() }
                        }
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("删除后无法恢复。")
            }
            .zyErrorBanner($viewModel.errorMessage)
        }
    }

    private var isSaveDisabled: Bool {
        if viewModel.isSaving { return true }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCat = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty || trimmedCat.isEmpty { return true }
        // File-backed edit rows are allowed to keep an empty body.
        if existingArticle?.fileUrl == nil, trimmedContent.isEmpty { return true }
        return false
    }

    private func save() async {
        if let article = existingArticle {
            let saved = await viewModel.updateArticle(
                id: article.id,
                title: title,
                content: content,
                category: category,
                tags: article.tags,
                fileUrl: article.fileUrl,
                fileType: article.fileType,
                fileSize: article.fileSize
            )
            if saved != nil { dismiss() }
        } else {
            let saved = await viewModel.createArticle(
                title: title,
                content: content,
                category: category
            )
            if saved != nil { dismiss() }
        }
    }
}
