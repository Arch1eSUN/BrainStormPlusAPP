import SwiftUI
import Supabase

// AI 草稿桥：POST /api/mobile/announcements/draft
// Web 等价实现：`generateAnnouncementDraft` in summary-actions.ts。
// iOS 端仅透传 Bearer JWT + { topic }，由 Web 路由调用 askAI 生成草稿。

public struct AnnouncementCreateView: View {
    @ObservedObject var viewModel: AnnouncementsListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var priority: Announcement.Priority = .normal
    /// Iter5 — 合并广播功能后,创建公告时可勾选"同时推送给所有人"。
    /// 默认关:大多数公告只需要进公告列表,不一定要全员推送。
    @State private var broadcastToAll: Bool = false

    @State private var isDrafting: Bool = false
    @State private var draftError: String?

    public var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("公告标题", text: $title)
                }

                Section {
                    // AI 智能起草按钮（对齐 Web ai-settings 布局：放在 content 字段上方）
                    Button {
                        Task { await draft() }
                    } label: {
                        HStack(spacing: BsSpacing.xs + 2) {
                            if isDrafting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isDrafting ? "AI 起草中…" : "AI 智能起草")
                                .font(BsTypography.caption)
                        }
                        .padding(.horizontal, BsSpacing.md)
                        .padding(.vertical, BsSpacing.xs + 2)
                        .background(
                            Capsule().fill(BsColor.brandAzure.opacity(0.12))
                        )
                        .foregroundStyle(BsColor.brandAzure)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        isDrafting
                        || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if let err = draftError {
                        Text(err)
                            .font(BsTypography.caption)
                            .foregroundStyle(BsColor.danger)
                    }

                    TextEditor(text: $content)
                        .frame(minHeight: 140)
                } header: {
                    Text("内容")
                } footer: {
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("填写标题后可使用 AI 智能起草。")
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                }

                Section("优先级") {
                    Picker("优先级", selection: $priority) {
                        ForEach(Announcement.Priority.allCases, id: \.self) { p in
                            Text(p.displayLabel).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    // Haptic removed: 用户反馈 picker 切换过密震动
                }

                Section {
                    Toggle("同时推送给所有人", isOn: $broadcastToAll)
                } footer: {
                    Text("勾选后,公告会作为系统通知推送给所有活跃用户(原「广播通知」功能)。")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                }
            }
            .navigationTitle("发布公告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let ok = await viewModel.create(
                                title: title,
                                content: content,
                                priority: priority,
                                broadcastToAll: broadcastToAll
                            )
                            if ok { dismiss() }
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("发布")
                        }
                    }
                    .disabled(viewModel.isSaving
                              || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - AI 起草桥接

    private func draft() async {
        let topic = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return }
        isDrafting = true
        draftError = nil
        defer { isDrafting = false }

        do {
            let session = try await supabase.auth.session
            let token = session.accessToken
            let url = AppEnvironment.webAPIBaseURL
                .appendingPathComponent("api/mobile/announcements/draft")
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 45

            let payload: [String: Any] = ["topic": topic]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                draftError = "网络异常，请重试"
                return
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode >= 400 {
                let msg = (json?["error"] as? String)
                    ?? String(data: data, encoding: .utf8)
                    ?? "HTTP \(http.statusCode)"
                draftError = "AI 起草失败：\(msg)"
                return
            }
            let draft = (json?["draft"] as? String)
                ?? (json?["content"] as? String)
                ?? ""
            guard !draft.isEmpty else {
                draftError = "AI 未返回草稿内容"
                return
            }
            // 成功：填入 content 字段（若用户已有输入，直接覆盖 —— 与 Web 行为一致；
            // 原始输入已经由 TODO 要求"失败时不清空"保护，仅成功时替换。）
            content = draft
        } catch {
            draftError = "AI 起草失败：\(ErrorLocalizer.localize(error))"
        }
    }
}
