import SwiftUI
import Charts
import PhotosUI

// ══════════════════════════════════════════════════
// AIAnalysisView — 1:1 port of
// BrainStorm+-Web/src/app/dashboard/ai-analysis/page.tsx
// Streams `/api/ai/analyze` SSE, renders the same intel-card layout.
// All strings 简体中文.
// ══════════════════════════════════════════════════

public struct AIAnalysisView: View {
    @StateObject private var viewModel: AIAnalysisViewModel
    @Environment(SessionManager.self) private var sessionManager

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    /// Iter 6 §A.9 — PhotosPicker selection. Up to 4 screenshots per run.
    /// We translate `PhotosPickerItem` → `Data` via `loadTransferable` and
    /// hand off to `viewModel.addScreenshot(data:)` so the VM owns lifecycle.
    @State private var pickerSelection: [PhotosPickerItem] = []

    @MainActor
    public init(isEmbedded: Bool = false) {
        _viewModel = StateObject(wrappedValue: AIAnalysisViewModel())
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
            if hasAccess {
                main
            } else {
                ContentUnavailableView(
                    "无权访问",
                    systemImage: "lock",
                    description: Text("需要「ai_media_analysis」能力才能使用媒体智能分析。请联系管理员分配。")
                )
            }
        }
        .navigationTitle("媒体智能分析")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if hasAccess && viewModel.provider == nil {
                await viewModel.loadProvider()
            }
        }
        .zyErrorBanner($viewModel.errorMessage)
    }

    private var hasAccess: Bool {
        let caps = RBACManager.shared.getEffectiveCapabilities(for: sessionManager.currentProfile)
        return caps.contains(.ai_media_analysis) || caps.contains(.media_ops)
    }

    private var main: some View {
        ScrollView {
            VStack(spacing: BsSpacing.lg + BsSpacing.xs) { // 20pt
                header

                if let msg = viewModel.providerLoadError, viewModel.provider == nil, isIdleLike {
                    providerWarning(msg)
                }

                if isIdleLike {
                    inputForm
                } else {
                    progressSection
                    scrapedDataSection
                    reportSection
                    actionBar
                }

                if case .idle = viewModel.pageState, viewModel.providerLoadError == nil {
                    emptyHint
                }
            }
            .padding(.horizontal, BsSpacing.lg)
            .padding(.top, BsSpacing.md)
            .padding(.bottom, BsSpacing.xxl)
        }
        .background(BsColor.pageBackground.ignoresSafeArea())
    }

    private var isIdleLike: Bool {
        switch viewModel.pageState {
        case .idle, .error: return true
        case .streaming, .done: return false
        }
    }

    // MARK: - Screenshot picker (Iter 6 §A.9)
    //
    // PhotosPicker is the iOS-26-native primitive for image selection — we
    // grab raw bytes via `loadTransferable(type: Data.self)` and forward to
    // the VM, which uploads to `chat-files` on submit. Total UX:
    //   1. Tap "上传截图" → system PhotosPicker sheet
    //   2. Pick up to 4 images
    //   3. Inline thumbnails appear with "X" remove buttons
    //   4. On 开始分析 → uploads run sequentially → SSE stream opens
    //
    // The legacy "截图链接" text-URL input is hidden behind a DisclosureGroup
    // so power users (web pasting Imgur URLs etc.) keep parity with web.

    @State private var showAdvancedImageURLs: Bool = false

    private var screenshotPickerSection: some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            label("截图（可选 · AI 视觉分析备用）", systemImage: "photo.on.rectangle.angled")

            // Picker button — system native, glass-effect button style.
            HStack(spacing: BsSpacing.sm) {
                PhotosPicker(
                    selection: $pickerSelection,
                    maxSelectionCount: 4,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: BsSpacing.xs + 2) {
                        if viewModel.isUploadingScreenshots {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "photo.badge.plus").font(.caption)
                        }
                        Text(viewModel.isUploadingScreenshots ? "上传中…" : "上传截图")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, BsSpacing.md)
                    .padding(.vertical, BsSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                            .fill(BsColor.brandAzure.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                                    .strokeBorder(BsColor.brandAzure.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .foregroundStyle(BsColor.brandAzure)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isUploadingScreenshots)
                .accessibilityLabel("从相册选择截图")

                if !viewModel.pickedScreenshots.isEmpty {
                    Text("已选 \(viewModel.pickedScreenshots.count) 张")
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkMuted)
                }

                Spacer(minLength: 0)
            }

            // Inline thumbnail strip
            if !viewModel.pickedScreenshots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BsSpacing.sm) {
                        ForEach(viewModel.pickedScreenshots) { shot in
                            screenshotThumbnail(shot)
                        }
                    }
                }
            }

            // Power-user URL fallback (collapsed by default) — keeps web parity.
            DisclosureGroup(isExpanded: $showAdvancedImageURLs) {
                VStack(alignment: .leading, spacing: BsSpacing.sm) {
                    TextEditor(text: $viewModel.imageUrlsText)
                        .frame(minHeight: 60)
                        .padding(BsSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                                .fill(BsColor.inkMuted.opacity(0.08))
                        )
                    Text("每行一个 http(s) URL 或以逗号分隔。AI 会直接读取截图中的用户名、点赞 / 收藏 / 评论 / 分享 / 播放等数据。")
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkMuted)
                }
                .padding(.top, BsSpacing.xs)
            } label: {
                HStack(spacing: BsSpacing.xs) {
                    Image(systemName: "link").font(.caption2)
                    Text("或粘贴截图 URL").font(.caption.weight(.medium))
                }
                .foregroundStyle(BsColor.inkMuted)
            }

            Text("Tip：当 AI 抓不到链接内容时（短链反爬 / 登录墙），上传截图让 AI 视觉读取数据。")
                .font(.caption2)
                .foregroundStyle(BsColor.inkMuted)
        }
        .onChange(of: pickerSelection) { _, newItems in
            handlePickerChange(newItems)
        }
    }

    private func screenshotThumbnail(_ shot: AIAnalysisViewModel.PickedScreenshot) -> some View {
        ZStack(alignment: .topTrailing) {
            if let img = UIImage(data: shot.imageData) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous)
                            .strokeBorder(BsColor.inkMuted.opacity(0.2), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous)
                    .fill(BsColor.inkMuted.opacity(0.1))
                    .frame(width: 72, height: 72)
                    .overlay(Image(systemName: "photo").foregroundStyle(BsColor.inkMuted))
            }

            // Remove "X" — top-right, ~22pt glass dot per design system.
            Button {
                Haptic.light()
                viewModel.removeScreenshot(id: shot.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white, BsColor.danger)
                    .background(Circle().fill(.white).frame(width: 14, height: 14))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel("移除截图")
        }
    }

    /// Translate `PhotosPickerItem` → `Data` and forward to VM. We avoid
    /// concurrent `loadTransferable` calls (PhotosPicker can deadlock if
    /// you fire many in parallel on the same backing store) by `await`ing
    /// each one in turn — typical 1-4 picks finish in <500ms total.
    private func handlePickerChange(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task { @MainActor in
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    viewModel.addScreenshot(data: data)
                }
            }
            // Reset selection so re-picking the same photo retriggers onChange.
            pickerSelection = []
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: BsSpacing.md) {
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BsColor.brandAzure, BsColor.brandMint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: BsSpacing.xxs) {
                Text("媒体智能分析")
                    .font(BsTypography.sectionTitle)
                    .foregroundStyle(BsColor.ink)
                HStack(spacing: BsSpacing.xs + 2) {
                    Text("社交媒体内容智能分析 ·")
                        .font(.footnote)
                        .foregroundStyle(BsColor.inkMuted)
                    if let p = viewModel.provider {
                        HStack(spacing: BsSpacing.xs) {
                            Image(systemName: "cpu")
                                .font(.caption2)
                            Text("\(p.providerName) / \(p.model)")
                                .font(.caption2)
                        }
                        .foregroundStyle(BsColor.brandAzure)
                    } else {
                        Text("未连接 AI")
                            .font(.caption2)
                            .foregroundStyle(BsColor.warning)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Provider warning

    private func providerWarning(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: BsSpacing.smd) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BsColor.warning)
                .font(.system(.body))
            VStack(alignment: .leading, spacing: BsSpacing.xs) {
                Text("未配置 AI 供应商").font(.subheadline.weight(.semibold)).foregroundStyle(BsColor.warning)
                Text(msg).font(.caption).foregroundStyle(BsColor.warning.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(BsSpacing.md + 2) // 14pt
        .background(
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .fill(BsColor.warning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .strokeBorder(BsColor.warning.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Input form

    private var inputForm: some View {
        BsContentCard {
            VStack(alignment: .leading, spacing: BsSpacing.lg + BsSpacing.xs) { // 20pt
                // Platform picker
                VStack(alignment: .leading, spacing: BsSpacing.smd) {
                    label("选择平台")
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: BsSpacing.sm), count: 3),
                        spacing: BsSpacing.sm
                    ) {
                        ForEach(MediaPlatform.allCases) { p in
                            platformTile(p)
                        }
                    }
                }

                // URL input
                VStack(alignment: .leading, spacing: BsSpacing.sm) {
                    label("内容链接", systemImage: "link")
                    HStack(spacing: BsSpacing.sm) {
                        Image(systemName: "globe")
                            .foregroundStyle(BsColor.inkMuted)
                        TextField(
                            "粘贴\(viewModel.platform.label)分享文案或内容链接…",
                            text: $viewModel.inputUrl,
                            axis: .vertical
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .lineLimit(1...4)
                    }
                    .padding(.horizontal, BsSpacing.md)
                    .padding(.vertical, BsSpacing.smd)
                    .background(
                        RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                            .fill(BsColor.inkMuted.opacity(0.08))
                    )
                }

                // Screenshots (Iter 6 §A.9 — fallback for anti-bot scrape)
                screenshotPickerSection

                if case let .error(msg) = viewModel.pageState, !msg.isEmpty {
                    errorRow(msg)
                }

                HStack {
                    Spacer()
                    Button {
                        // Haptic removed: AI 分析触发非关键 mutation
                        viewModel.submit()
                    } label: {
                        HStack(spacing: BsSpacing.xs + 2) { // 6pt
                            Image(systemName: "paperplane.fill")
                            Text("开始分析").font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, BsSpacing.lg - 6) // 18pt
                        .padding(.vertical, BsSpacing.smd)
                        .background(
                            LinearGradient(
                                colors: [BsColor.brandAzure, BsColor.brandMint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
                        .opacity(viewModel.canSubmit ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canSubmit)
                    .accessibilityLabel("开始分析")
                }
            }
        }
    }

    private func platformTile(_ p: MediaPlatform) -> some View {
        let selected = viewModel.platform == p
        return Button {
            // Haptic removed: 用户反馈 chip 切换过密震动
            viewModel.platform = p
        } label: {
            VStack(spacing: BsSpacing.xs + 2) { // 6pt
                Image(systemName: p.icon)
                    .font(.system(.title3))
                Text(p.label)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BsSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                    .fill(selected ? BsColor.brandAzure.opacity(0.08) : BsColor.inkMuted.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                            .strokeBorder(selected ? BsColor.brandAzure : BsColor.inkMuted.opacity(0.18), lineWidth: selected ? 1.5 : 1)
                    )
            )
            .foregroundStyle(selected ? BsColor.brandAzure : BsColor.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择平台 \(p.label)")
    }

    private func label(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: BsSpacing.xs + 2) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .font(BsTypography.label)
                .kerning(0.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(BsColor.inkMuted)
    }

    private func errorRow(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: BsSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(BsColor.danger)
            VStack(alignment: .leading, spacing: BsSpacing.xxs) {
                Text("分析失败").font(.caption.weight(.semibold)).foregroundStyle(BsColor.danger)
                Text(msg).font(.caption).foregroundStyle(BsColor.danger.opacity(0.8))
            }
            Spacer()
            Button {
                // Haptic removed: 用户反馈辅助按钮过密震动
                viewModel.reset()
            } label: {
                HStack(spacing: BsSpacing.xs) {
                    Image(systemName: "arrow.clockwise").font(.caption2)
                    Text("重试").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, BsSpacing.smd)
                .padding(.vertical, BsSpacing.xs + 2)
                .background(RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous).fill(BsColor.danger.opacity(0.12)))
                .foregroundStyle(BsColor.danger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重试分析")
        }
        .padding(BsSpacing.smd)
        .background(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous).fill(BsColor.danger.opacity(0.06)))
    }

    // MARK: - Progress section (iOS-native multi-stage list)

    @State private var isLogExpanded: Bool = false

    @ViewBuilder
    private var progressSection: some View {
        if let progress = viewModel.progress {
            BsContentCard(padding: .small) {
                VStack(alignment: .leading, spacing: BsSpacing.md) {
                    progressHeader(progress: progress)

                    Divider().opacity(0.4)

                    VStack(spacing: BsSpacing.xs + 2) {
                        ForEach(AIAnalysisPhase.ordered, id: \.self) { phase in
                            stageRow(phase: phase, current: progress.phase)
                        }
                    }

                    if !viewModel.stageLogs.isEmpty {
                        Divider().opacity(0.4)
                        detailDisclosure
                    }
                }
            }
        }
    }

    private func progressHeader(progress: AIAnalysisProgress) -> some View {
        HStack(alignment: .center, spacing: BsSpacing.sm) {
            Image(systemName: viewModel.pageState == .done ? "checkmark.seal.fill" : "sparkles")
                .font(.system(.body))
                .foregroundStyle(viewModel.pageState == .done ? BsColor.success : BsColor.brandAzure)
            VStack(alignment: .leading, spacing: BsSpacing.xxs) {
                Text(viewModel.pageState == .done ? "分析完成" : progress.phase.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BsColor.ink)
                Text(stageSummaryText(progress: progress))
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkMuted)
            }
            Spacer(minLength: 0)
            // Compact percent badge — replaces the web <progress> bar.
            Text("\(max(0, min(100, progress.percent)))%")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(viewModel.pageState == .done ? BsColor.success : BsColor.brandAzure)
                .padding(.horizontal, BsSpacing.sm)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        (viewModel.pageState == .done ? BsColor.success : BsColor.brandAzure).opacity(0.1)
                    )
                )
                .contentTransition(.numericText())
                .animation(BsMotion.Anim.smooth, value: progress.percent)
        }
    }

    private func stageSummaryText(progress: AIAnalysisProgress) -> String {
        let total = AIAnalysisPhase.ordered.count
        let history = viewModel.phaseHistory.filter { AIAnalysisPhase.ordered.contains($0) }
        let completed = history.filter { $0 != progress.phase }.count
        if let dur = viewModel.totalDurationSeconds, viewModel.pageState == .done {
            return String(format: "已完成 %d 个阶段，耗时 %.1fs", history.count, dur)
        }
        return "进度 \(min(completed + 1, total)) / \(total) · \(progress.message)"
    }

    @ViewBuilder
    private func stageRow(phase: AIAnalysisPhase, current: AIAnalysisPhase) -> some View {
        let history = viewModel.phaseHistory
        let isDone = viewModel.pageState == .done
        let isCurrent = !isDone && (current == phase)
        let isComplete = (isDone && history.contains(phase)) || (history.contains(phase) && !isCurrent)
        let isPending = !history.contains(phase) && !isCurrent

        let log = viewModel.stageLogs.last(where: { $0.phase == phase })

        HStack(alignment: .center, spacing: BsSpacing.smd) {
            stageGlyph(phase: phase, isCurrent: isCurrent, isComplete: isComplete, isPending: isPending)

            VStack(alignment: .leading, spacing: 2) {
                Text(phase.label)
                    .font(.caption.weight(isPending ? .regular : .semibold))
                    .foregroundStyle(stageTextColor(isCurrent: isCurrent, isComplete: isComplete, isPending: isPending))
                if isCurrent, let log {
                    Text(log.message)
                        .font(.caption2)
                        .foregroundStyle(BsColor.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            if let dur = log?.durationSeconds, isComplete {
                Text(String(format: "%.1fs", dur))
                    .font(BsTypography.meta.monospacedDigit())
                    .foregroundStyle(BsColor.inkMuted)
            } else if isCurrent {
                Text("进行中")
                    .font(BsTypography.meta)
                    .foregroundStyle(BsColor.brandAzure)
            }
        }
    }

    private func stageGlyph(
        phase: AIAnalysisPhase,
        isCurrent: Bool,
        isComplete: Bool,
        isPending: Bool
    ) -> some View {
        Group {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BsColor.success)
            } else if isCurrent {
                if #available(iOS 17.0, *) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(BsColor.brandAzure)
                        .symbolEffect(.pulse, options: .repeating)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(BsColor.brandAzure)
                }
            } else {
                Image(systemName: "circle.dotted")
                    .foregroundStyle(BsColor.inkMuted.opacity(0.5))
            }
        }
        .font(.system(.body))
        .frame(width: 22, height: 22)
    }

    private func stageTextColor(isCurrent: Bool, isComplete: Bool, isPending: Bool) -> Color {
        if isCurrent { return BsColor.brandAzure }
        if isComplete { return BsColor.ink }
        return BsColor.inkMuted
    }

    // ── Expandable detail log ──

    private var detailDisclosure: some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            Button {
                withAnimation(BsMotion.Anim.smooth) {
                    isLogExpanded.toggle()
                }
            } label: {
                HStack(spacing: BsSpacing.xs + 2) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.caption)
                    Text(isLogExpanded ? "收起阶段日志" : "展开阶段日志")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isLogExpanded ? 180 : 0))
                        .animation(BsMotion.Anim.smooth, value: isLogExpanded)
                }
                .foregroundStyle(BsColor.inkMuted)
                .padding(.vertical, BsSpacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLogExpanded ? "收起阶段日志" : "展开阶段日志")

            if isLogExpanded {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: BsSpacing.xs + 2) {
                        ForEach(viewModel.stageLogs) { entry in
                            stageLogRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 240)
                .padding(BsSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous)
                        .fill(BsColor.inkMuted.opacity(0.05))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func stageLogRow(_ entry: AIAnalysisStageLog) -> some View {
        HStack(alignment: .top, spacing: BsSpacing.sm) {
            Image(systemName: entry.phase.icon)
                .font(.caption2)
                .foregroundStyle(BsColor.brandAzure)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: BsSpacing.xs) {
                    Text(entry.phase.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BsColor.ink)
                    Text(Self.timeString(entry.timestamp))
                        .font(BsTypography.meta.monospacedDigit())
                        .foregroundStyle(BsColor.inkMuted)
                    if let dur = entry.durationSeconds {
                        Text(String(format: "· %.2fs", dur))
                            .font(BsTypography.meta.monospacedDigit())
                            .foregroundStyle(BsColor.inkMuted.opacity(0.7))
                    }
                }
                Text(entry.message)
                    .font(.caption2)
                    .foregroundStyle(BsColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    private static func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    // MARK: - Scraped data

    @ViewBuilder
    private var scrapedDataSection: some View {
        if let data = viewModel.scrapedData, !data.isEmpty {
            BsContentCard(padding: .small) {
                DisclosureGroup {
                    ScrollView(.vertical) {
                        Text(Self.prettyJson(data))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(BsColor.inkMuted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(BsSpacing.sm)
                    }
                    .frame(maxHeight: 260)
                } label: {
                    HStack(spacing: BsSpacing.xs + 2) {
                        Image(systemName: "doc.text").font(.caption)
                        Text("抓取数据预览").font(.caption.weight(.medium))
                    }
                    .foregroundStyle(BsColor.inkMuted)
                }
            }
        }
    }

    private static func prettyJson(_ dict: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return "\(dict)"
        }
        return s
    }

    // MARK: - Report (intel card)

    @ViewBuilder
    private var reportSection: some View {
        BsContentCard(padding: .small) {
            VStack(alignment: .leading, spacing: BsSpacing.smd) {
                HStack(spacing: BsSpacing.sm) {
                    Image(systemName: "brain.head.profile").foregroundStyle(BsColor.brandAzure).font(.caption)
                    Text("智能情报报告").font(.subheadline.weight(.semibold)).foregroundStyle(BsColor.ink)
                    if viewModel.pageState == .streaming {
                        HStack(spacing: BsSpacing.xs) {
                            Circle().fill(BsColor.brandAzure).frame(width: 6, height: 6)
                            Text("生成中").font(.caption2)
                        }
                        .foregroundStyle(BsColor.brandAzure)
                    }
                    Spacer(minLength: 0)
                    if viewModel.pageState == .done, !viewModel.report.isEmpty {
                        Button {
                            Haptic.light()
                            UIPasteboard.general.string = viewModel.report
                        } label: {
                            HStack(spacing: BsSpacing.xs) {
                                Image(systemName: "doc.on.doc").font(.caption2)
                                Text("复制").font(.caption)
                            }
                            .foregroundStyle(BsColor.inkMuted)
                            .padding(.horizontal, BsSpacing.smd)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("复制报告内容")
                    }
                }
                Divider()
                reportBody
            }
        }
    }

    @ViewBuilder
    private var reportBody: some View {
        if viewModel.report.isEmpty {
            VStack(spacing: BsSpacing.sm) {
                Image(systemName: "exclamationmark.circle")
                    .font(.title3)
                    .foregroundStyle(BsColor.warning)
                Text("等待 AI 输出…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BsColor.warning)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BsSpacing.xl)
        } else {
            switch MediaAnalysisParser.parse(viewModel.report) {
            case .ok(let m):
                IntelReportView(result: m)
            case .failed(let reason):
                VStack(alignment: .leading, spacing: BsSpacing.sm) {
                    HStack(alignment: .top, spacing: BsSpacing.xs + 2) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(BsColor.warning)
                        VStack(alignment: .leading, spacing: BsSpacing.xxs) {
                            Text("AI 输出未匹配情报卡结构，显示原始内容：")
                                .font(.caption.weight(.semibold)).foregroundStyle(BsColor.warning)
                            Text(reason).font(.caption2).foregroundStyle(BsColor.warning.opacity(0.8))
                        }
                    }
                    Text(viewModel.report)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(BsColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(BsSpacing.smd)
                        .background(RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous).fill(BsColor.inkMuted.opacity(0.06)))
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: BsSpacing.md) {
            Spacer()
            if viewModel.pageState == .streaming {
                Button(role: .destructive) {
                    // Haptic removed: 停止生成非真删 mutation
                    viewModel.stop()
                } label: {
                    HStack(spacing: BsSpacing.xs + 2) {
                        Image(systemName: "stop.circle").font(.caption)
                        Text("停止生成").font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, BsSpacing.md + 2) // 14pt
                    .padding(.vertical, BsSpacing.sm)
                    .background(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous).strokeBorder(BsColor.danger.opacity(0.5)))
                    .foregroundStyle(BsColor.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("停止当前分析")
            }
            Button {
                // Haptic removed: 用户反馈辅助按钮过密震动
                viewModel.reset()
            } label: {
                HStack(spacing: BsSpacing.xs + 2) {
                    Image(systemName: "arrow.clockwise").font(.caption)
                    Text("新的分析").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, BsSpacing.md + 2)
                .padding(.vertical, BsSpacing.sm)
                .background(
                    LinearGradient(
                        colors: [BsColor.brandAzure, BsColor.brandMint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开始新的分析")
        }
    }

    // MARK: - Empty hint

    private var emptyHint: some View {
        BsContentCard(padding: .large) {
            VStack(spacing: BsSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(BsColor.brandAzure)
                    .padding(BsSpacing.md)
                    .background(Circle().fill(BsColor.brandAzure.opacity(0.1)))
                Text("开始你的第一个分析")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BsColor.ink)
                Text("输入社交媒体链接 + 截图（可选），AI 会抽取平台 / 作者 / 互动数据 / 卖点 / 受众，并输出三档投流预算与 10 关键词的情报卡片。")
                    .font(.caption)
                    .foregroundStyle(BsColor.inkMuted)
                    .multilineTextAlignment(.center)
                HStack(spacing: BsSpacing.lg) {
                    hintChip(icon: "globe", text: "支持 9 大平台")
                    hintChip(icon: "photo", text: "多模态截图")
                    hintChip(icon: "doc.text.magnifyingglass", text: "结构化情报卡")
                }
                .padding(.top, BsSpacing.xs + 2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func hintChip(icon: String, text: String) -> some View {
        HStack(spacing: BsSpacing.xs) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2)
        }
        .foregroundStyle(BsColor.inkMuted)
    }
}

// MARK: - Intel Report Subviews

private struct IntelReportView: View {
    let result: MediaAnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: BsSpacing.md + 2) { // 14pt
            if let summary = result.summary, !summary.isEmpty {
                summaryBanner(summary)
            }

            section(icon: "person.text.rectangle", title: "基础信息") {
                basicsGrid
            }

            section(icon: "chart.bar.fill", title: "互动数据") {
                metricsChart
            }

            section(icon: "target", title: "内容") {
                contentBlock
            }

            section(icon: "scale.3d", title: "评估") {
                evaluationBlock
            }

            section(icon: "dollarsign.circle.fill", title: "投流策略") {
                promotionBlock
            }

            section(icon: "key.fill", title: "关键词") {
                keywordsBlock
            }

            if let notes = result.otherNotes, !notes.isEmpty {
                section(icon: "note.text", title: "其他备注") {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(BsColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // ── Subviews ──

    private func summaryBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            Text("一句话速览")
                .font(BsTypography.captionSmall)
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(BsColor.brandAzure)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(BsColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BsSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BsColor.brandAzure.opacity(0.08), BsColor.brandAzure.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .strokeBorder(BsColor.brandAzure.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func section<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.smd) {
            HStack(spacing: BsSpacing.xs + 2) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(BsTypography.label).kerning(0.6).textCase(.uppercase)
            }
            .foregroundStyle(BsColor.inkMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BsSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                .fill(BsColor.inkMuted.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
                        .strokeBorder(BsColor.inkMuted.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var basicsGrid: some View {
        let b = result.basics
        return VStack(alignment: .leading, spacing: BsSpacing.smd) {
            HStack(alignment: .top, spacing: BsSpacing.md) {
                infoCell(label: "平台", valueView: AnyView(
                    Text(b.platform.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, BsSpacing.sm)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous).fill(BsColor.brandAzure.opacity(0.1))
                        )
                        .foregroundStyle(BsColor.brandAzure)
                ))
                infoCell(label: "账号", text: b.authorHandle.map { "@\($0)" })
            }
            HStack(alignment: .top, spacing: BsSpacing.md) {
                infoCell(label: "发布时间", text: b.publishTime)
            }
            if let title = b.coverTitle {
                infoCell(label: "标题 / 封面文字", text: title, fullWidth: true)
            }
        }
    }

    private func infoCell(label: String, text: String?, fullWidth: Bool = false) -> some View {
        infoCell(label: label, valueView: AnyView(
            Text(text ?? "—")
                .font(.caption)
                .foregroundStyle(text == nil ? BsColor.inkMuted : BsColor.ink)
        ), fullWidth: fullWidth)
    }

    private func infoCell(label: String, valueView: AnyView, fullWidth: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(BsTypography.label)
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(BsColor.inkMuted)
            valueView
        }
        .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
    }

    private struct MetricDatum: Identifiable {
        let id = UUID()
        let label: String
        let value: Int
        let emoji: String
    }

    private var metricsChart: some View {
        let m = result.metrics
        let data: [MetricDatum] = [
            .init(label: "点赞", value: m.likes ?? 0, emoji: "❤️"),
            .init(label: "收藏", value: m.collects ?? 0, emoji: "⭐"),
            .init(label: "评论", value: m.comments ?? 0, emoji: "💬"),
            .init(label: "分享", value: m.shares ?? 0, emoji: "🔄"),
            .init(label: "播放", value: m.plays ?? 0, emoji: "▶️"),
        ]
        let allZero = data.allSatisfy { $0.value == 0 }

        return VStack(alignment: .leading, spacing: BsSpacing.smd) {
            if !allZero {
                Chart(data) { d in
                    BarMark(
                        x: .value("指标", d.label),
                        y: .value("数量", d.value)
                    )
                    .foregroundStyle(BsColor.brandAzure.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 140)
                .chartYAxis {
                    // chart axis: fixed size —— SwiftUI Chart axis labels 默认走
                    // system default；此处未自定义 font，保持默认。
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                }
            }

            HStack(spacing: BsSpacing.xs + 2) {
                ForEach(data) { d in
                    VStack(spacing: BsSpacing.xs) {
                        Text("\(d.emoji) \(d.label)")
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                        Text(d.value > 0 ? Self.formatInt(d.value) : "—")
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(d.value > 0 ? BsColor.ink : BsColor.inkMuted)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BsSpacing.xs + 2)
                    .background(RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous).fill(BsColor.inkMuted.opacity(0.05)))
                }
            }
        }
    }

    private static func formatInt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var contentBlock: some View {
        VStack(alignment: .leading, spacing: BsSpacing.smd) {
            VStack(alignment: .leading, spacing: 3) {
                Text("主题").font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                Text(result.content.theme).font(.caption).foregroundStyle(BsColor.ink)
            }
            if !result.content.sellingPoints.isEmpty {
                VStack(alignment: .leading, spacing: BsSpacing.xs) {
                    Text("核心卖点").font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                    ForEach(Array(result.content.sellingPoints.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: BsSpacing.xs) {
                            Text("•").foregroundStyle(BsColor.brandAzure)
                            Text(item).font(.caption).foregroundStyle(BsColor.ink)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("目标受众").font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                Text(result.content.targetAudience).font(.caption).foregroundStyle(BsColor.ink)
            }
        }
    }

    private var evaluationBlock: some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            evaluationList(title: "✅ 优势", items: result.evaluation.strengths, color: BsColor.success)
            evaluationList(title: "🔧 改进", items: result.evaluation.improvements, color: BsColor.warning)
        }
    }

    private func evaluationList(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            Text(title)
                .font(BsTypography.captionSmall.weight(.bold))
                .kerning(0.4)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: BsSpacing.xs) {
                        Text("•").foregroundStyle(color)
                        Text(item).font(.caption).foregroundStyle(BsColor.ink)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BsSpacing.smd)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous)
                        .strokeBorder(color.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var promotionBlock: some View {
        let p = result.paidPromotion
        return VStack(alignment: .leading, spacing: BsSpacing.smd) {
            HStack(spacing: BsSpacing.xs + 2) {
                budgetTile(label: "低档", tier: p.budgetTiers.low, accent: BsColor.inkMuted)
                budgetTile(label: "中档", tier: p.budgetTiers.medium, accent: BsColor.brandAzure)
                budgetTile(label: "高档", tier: p.budgetTiers.high, accent: BsColor.brandAzure)
            }
            if !p.audienceTargeting.isEmpty {
                VStack(alignment: .leading, spacing: BsSpacing.xs) {
                    Text("定向人群").font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                    chipRow(items: p.audienceTargeting, color: BsColor.brandAzure)
                }
            }
            if !p.bestTimeSlots.isEmpty {
                VStack(alignment: .leading, spacing: BsSpacing.xs) {
                    Text("最佳投放时段").font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                    chipRow(items: p.bestTimeSlots, color: BsColor.brandMint)
                }
            }
        }
    }

    private func budgetTile(label: String, tier: MediaAnalysisResult.PaidPromotion.Tier, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            HStack {
                Text(label).font(BsTypography.label).textCase(.uppercase).foregroundStyle(BsColor.inkMuted)
                Spacer()
                Text(tier.dailyCny).font(.caption.weight(.bold)).foregroundStyle(accent)
            }
            Text(tier.expected).font(.caption2).foregroundStyle(BsColor.inkMuted).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BsSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous)
                .fill(accent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: BsRadius.sm, style: .continuous)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var keywordsBlock: some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm) {
            if !result.keywords.brand.isEmpty {
                keywordGroup(title: "Brand · 品牌词", items: result.keywords.brand, color: BsColor.brandAzure)
            }
            if !result.keywords.category.isEmpty {
                keywordGroup(title: "Category · 品类词", items: result.keywords.category, color: BsColor.brandAzure)
            }
            if !result.keywords.longTail.isEmpty {
                keywordGroup(title: "Long-tail · 长尾词", items: result.keywords.longTail, color: BsColor.warning)
            }
        }
    }

    private func keywordGroup(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            Text(title).font(BsTypography.label).textCase(.uppercase).foregroundStyle(color)
            chipRow(items: items, color: color, prefix: "#")
        }
    }

    private func chipRow(items: [String], color: Color, prefix: String = "") -> some View {
        FlowLayout(spacing: BsSpacing.xs + 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text("\(prefix)\(item)")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, BsSpacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: BsRadius.xs + 2, style: .continuous) // 6pt chip
                            .fill(color.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: BsRadius.xs + 2, style: .continuous)
                                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
                            )
                    )
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - FlowLayout (SwiftUI Layout for chip wrapping)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var h: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                h += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        h += rowHeight
        return CGSize(width: width == .infinity ? rowWidth : width, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
