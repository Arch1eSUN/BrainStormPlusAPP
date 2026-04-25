import SwiftUI

/// Phase 1.1 — @ 提及成员选择器
///
/// 触发: 用户在输入框里打下 `@` 字符,且光标后没有空格 → 出现一个 bottom sheet
/// 列出可 mention 成员;模糊搜索按 displayName / fullName / email 前缀+包含
/// 同时匹配。点击后:
///   1. 把当前输入栏里的 `@xxx` 片段替换成 `@DisplayName ` (含末尾空格)
///   2. 把 `mentioned_user_id` 加到调用方的 mentioned 集合(用于消息高亮)
///
/// 视觉: 不是 Slack 的纯文本列表 —— 我们用 BsContentCard row + 28pt 圆头像 +
/// Inter body 主名 + caption 副位/部门,跟 ChatList row 同一套语言。
struct MentionPickerSheet: View {
    let candidates: [Profile]
    /// 当前输入栏里 `@` 之后的查询片段(不含 `@` 本身)。空串表示用户刚打 `@`,
    /// 此时显示完整列表。
    @Binding var query: String
    /// 命中 → 把 (Profile, displayName) 回调给 caller 做文本插入。
    let onPick: (Profile) -> Void
    let onDismiss: () -> Void

    @State private var localQuery: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                BsColor.pageBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 自带搜索条 —— 让用户即使在 sheet 内也能进一步过滤,
                    // 不必关闭 sheet 回去改 `@xxx` 片段。
                    HStack(spacing: BsSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(BsColor.inkMuted)
                        TextField("搜索成员…", text: $localQuery)
                            .font(BsTypography.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, BsSpacing.md)
                    .padding(.vertical, BsSpacing.sm + 2)
                    .background(BsColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                    .padding(.horizontal, BsSpacing.lg)
                    .padding(.top, BsSpacing.md)

                    if filtered.isEmpty {
                        Spacer()
                        VStack(spacing: BsSpacing.sm) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 28))
                                .foregroundStyle(BsColor.inkFaint)
                            Text(localQuery.isEmpty ? "暂无可提及成员" : "没有匹配的成员")
                                .font(BsTypography.bodySmall)
                                .foregroundStyle(BsColor.inkMuted)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: BsSpacing.xs) {
                                ForEach(filtered, id: \.id) { profile in
                                    Button {
                                        Haptic.light()
                                        onPick(profile)
                                    } label: {
                                        memberRow(profile)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, BsSpacing.lg)
                            .padding(.vertical, BsSpacing.md)
                        }
                    }
                }
            }
            .navigationTitle("提及")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { onDismiss() }
                        .foregroundStyle(BsColor.brandAzure)
                }
            }
            .onAppear { localQuery = query }
            .onChange(of: localQuery) { _, new in query = new }
        }
        .presentationDetents([.fraction(0.45), .large])
        .presentationDragIndicator(.visible)
    }

    private var filtered: [Profile] {
        let q = localQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return candidates }
        return candidates.filter { p in
            // Iter 7 Fix 2 — 模糊匹配同时覆盖 fullName / displayName / email username,
            // 让用户输入"张"或"zhangsan"或邮箱前缀都能命中。
            let emailUser: String = {
                guard let e = p.email else { return "" }
                return e.split(separator: "@").first.map(String.init) ?? e
            }()
            let hay = [p.fullName, p.displayName, p.email, emailUser]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return hay.contains(q)
        }
    }

    /// Iter 7 Fix 2 — 中文姓名优先。`fullName` 是 HR 维护的中文真名（"张三"），
    /// 只有它缺席时才退到 `displayName`,最后才用 email 用户名做兜底。
    /// 调用方插入到输入栏时也用同一规则,做到 UI 看到什么 → 插入什么。
    static func displayLabel(for p: Profile) -> String {
        if let name = p.fullName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return name
        }
        if let name = p.displayName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return name
        }
        if let email = p.email, let user = email.split(separator: "@").first {
            return String(user)
        }
        return "未命名"
    }

    @ViewBuilder
    private func memberRow(_ p: Profile) -> some View {
        HStack(spacing: BsSpacing.md) {
            avatar(for: p)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().stroke(BsColor.borderSubtle, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                // 中文姓名优先 —— displayLabel 已经按 fullName → displayName → email
                // 顺序兜底,英文邮箱前缀只作为最后一道保底。
                Text(Self.displayLabel(for: p))
                    .font(BsTypography.cardSubtitle)
                    .foregroundStyle(BsColor.ink)
                    .lineLimit(1)
                // 副位:优先部门,再 fall back 到 position / email user 让用户区分同名
                if let secondary = secondaryLine(for: p) {
                    Text(secondary)
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "at")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BsColor.brandAzure.opacity(0.5))
        }
        .padding(.horizontal, BsSpacing.md)
        .padding(.vertical, BsSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .fill(BsColor.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    /// 副行:部门 → 职位 → email username。任一非空就出。
    private func secondaryLine(for p: Profile) -> String? {
        if let dept = p.department, !dept.isEmpty { return dept }
        if let pos = p.position, !pos.isEmpty { return pos }
        if let email = p.email, let user = email.split(separator: "@").first {
            return String(user)
        }
        return nil
    }

    @ViewBuilder
    private func avatar(for p: Profile) -> some View {
        if let urlStr = p.avatarUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: avatarFallback(for: p)
                }
            }
        } else {
            avatarFallback(for: p)
        }
    }

    @ViewBuilder
    private func avatarFallback(for p: Profile) -> some View {
        // 头像首字: 中文姓名优先取姓; 邮箱用户名兜底。
        let initial = Self.displayLabel(for: p).prefix(1)
        ZStack {
            BsColor.brandAzure.opacity(0.18)
            Text(String(initial).uppercased())
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.brandAzureDark)
        }
    }
}
