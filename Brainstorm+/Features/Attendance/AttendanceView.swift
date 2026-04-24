import SwiftUI
import Combine

public struct AttendanceView: View {
    @StateObject private var viewModel = AttendanceViewModel()
    @State private var isPulsing = false
    /// Drives the heartbeat ring behind the clock button while the app is
    /// waiting on either geolocation resolution or a server round-trip.
    /// Mirrors the Web `acquiring | in-fence` gating on the outer rings.
    @State private var isAwaitingSuccess = false

    // Phase 3: isEmbedded parameterization
    public let isEmbedded: Bool

    public init(isEmbedded: Bool = false) {
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
        ZStack {
            // Ambient 弥散底 —— Azure/Mint blobs 漂在暖米纸底上。
            // AttendanceView 常被作为嵌入视图（Dashboard widget），
            // 但即便嵌入，多一层 ambient 也不会干扰父级（blobs 透明度 ≤ 0.15）。
            BsColor.pageBackground.ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: BsSpacing.lg + 4) {
                header
                locationCard
                primaryButton
                messageBanner
                summaryGrid
            }
            .padding(BsSpacing.xl)
        }
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xxl + 4, style: .continuous))
        .bsShadow(BsShadow.md)
        .onAppear { isPulsing = true }
        // Heartbeat ring is live while loading OR immediately after a
        // fence is acquired but before success ripple fires.
        .onChange(of: viewModel.isLoading) { _, newValue in
            isAwaitingSuccess = newValue
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: BsSpacing.xs) {
                Text("每日打卡")
                    .font(BsTypography.sectionTitle)
                    .foregroundStyle(BsColor.ink)

                Text(Date().formatted(date: .complete, time: .omitted))
                    .font(BsTypography.bodySmall)
                    .foregroundStyle(BsColor.inkMuted)
            }

            Spacer()

            fencePill
        }
    }

    private var fencePill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(fenceTone)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 1).repeatForever(), value: isPulsing)

            Text(fenceLabel)
                .font(BsTypography.captionSmall)
                .foregroundStyle(fenceTone)
        }
        .padding(.horizontal, BsSpacing.sm + 2)
        .padding(.vertical, 6)
        // Fusion glass pill —— tone-tinted liquid glass
        .glassEffect(
            .regular.tint(fenceTone.opacity(0.20)),
            in: Capsule()
        )
    }

    // MARK: - Location card

    private var locationCard: some View {
        ZStack {
            // Fusion glass envelope —— 取代 solid surfaceSecondary + hairline。
            Color.clear
                .frame(height: 140)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous)
                )

            ZStack {
                Circle()
                    .stroke(BsColor.brandAzure.opacity(0.2), lineWidth: 1)
                    .frame(width: 80, height: 80)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0 : 1)

                Circle()
                    .fill(BsColor.brandAzure.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .opacity(isPulsing ? 0.3 : 1)

                Image(systemName: "location.fill")
                    .foregroundStyle(BsColor.brandAzure)
                    .font(.system(.title3))
            }
            .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isPulsing)

            VStack {
                Spacer()
                HStack {
                    Text(viewModel.currentLocationName ?? "正在获取位置…")
                        .font(BsTypography.captionSmall)
                        .foregroundStyle(BsColor.inkMuted)
                    Spacer()
                }
                .padding(BsSpacing.md)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.xl, style: .continuous))
    }

    // MARK: - Button

    private var primaryButton: some View {
        ZStack {
            // Heartbeat outer rings — only while actively awaiting the
            // server or geolocation. Two layered circles with staggered
            // durations (mirrors the Framer Motion `scale: [0.9, 1.08,
            // 0.9]` on clock-section.tsx L188-200).
            if isAwaitingSuccess && !viewModel.justSucceeded {
                Capsule()
                    .stroke(buttonTone.opacity(0.35), lineWidth: 2)
                    .scaleEffect(isAwaitingSuccess ? 1.08 : 1.0)
                    .opacity(isAwaitingSuccess ? 0 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: isAwaitingSuccess
                    )
                    .frame(height: 56)

                Capsule()
                    .fill(buttonTone.opacity(0.18))
                    .scaleEffect(isAwaitingSuccess ? 1.12 : 1.0)
                    .opacity(isAwaitingSuccess ? 0 : 0.4)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: false),
                        value: isAwaitingSuccess
                    )
                    .frame(height: 56)
            }

            // Success ripple — one-shot green burst when the server
            // confirms the punch. VM auto-clears `justSucceeded` after
            // 1.2s so this doesn't require a matched `withAnimation`.
            if viewModel.justSucceeded {
                Capsule()
                    .fill(BsColor.success.opacity(0.35))
                    .scaleEffect(viewModel.justSucceeded ? 1.4 : 0.9)
                    .opacity(viewModel.justSucceeded ? 0 : 0.7)
                    .animation(.easeOut(duration: 0.8), value: viewModel.justSucceeded)
                    .frame(height: 56)
            }

            // Fusion primary CTA —— Liquid Glass tinted capsule with
            // tone-aware haptic（Azure=上班 / Warning=下班 / Faint=已完成）。
            Button(action: {
                switch viewModel.clockState {
                case .ready: Haptic.medium()
                case .clockedIn: Haptic.rigid()
                case .done: Haptic.soft()
                }
                Task { await viewModel.punch() }
            }) {
                HStack(spacing: BsSpacing.sm) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(buttonTone)
                    } else {
                        Image(systemName: buttonIcon)
                            .font(.system(.body))
                    }
                    Text(buttonLabel)
                        .font(Font.custom("Outfit-Bold", size: 16, relativeTo: .body))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BsSpacing.lg)
                .glassEffect(
                    .regular.tint(buttonTone.opacity(buttonEnabled ? 0.35 : 0.15)).interactive(),
                    in: Capsule()
                )
                .foregroundStyle(buttonEnabled ? buttonTone : BsColor.inkFaint)
                .shadow(color: buttonEnabled ? buttonTone.opacity(0.3) : .clear, radius: 8, y: 4)
            }
            .disabled(!buttonEnabled)
            .buttonStyle(SquishyButtonStyle())
        }
    }

    private var buttonEnabled: Bool {
        viewModel.hasLocation && !viewModel.isLoading && !viewModel.isInitializing && viewModel.clockState != .done
    }

    private var buttonLabel: String {
        if viewModel.isInitializing { return "加载中…" }
        if viewModel.isLoading { return "处理中…" }
        switch viewModel.clockState {
        case .ready: return viewModel.hasLocation ? "上班打卡" : "等待定位"
        case .clockedIn: return "下班打卡"
        case .done: return "今日已完成"
        }
    }

    private var buttonIcon: String {
        if viewModel.clockState == .done { return "checkmark.circle.fill" }
        if viewModel.clockState == .clockedIn { return "rectangle.portrait.and.arrow.right" }
        return viewModel.hasLocation ? "hand.tap.fill" : "lock.fill"
    }

    private var buttonTone: Color {
        if !buttonEnabled { return BsColor.inkFaint.opacity(0.3) }
        switch viewModel.clockState {
        case .ready: return BsColor.brandAzure
        case .clockedIn: return BsColor.warning
        case .done: return BsColor.inkFaint.opacity(0.3)
        }
    }

    // MARK: - Message banner

    @ViewBuilder
    private var messageBanner: some View {
        if let msg = viewModel.successMessage {
            HStack(spacing: BsSpacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(.caption))
                Text(msg)
                    .font(BsTypography.caption)
            }
            .foregroundStyle(BsColor.success)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let err = viewModel.errorMessage {
            // 分辨错误类型：定位 / 网络 / 其他 —— 让用户知道下一步该做什么
            HStack(spacing: BsSpacing.xs) {
                Image(systemName: errorIcon(for: err))
                    .font(.system(.caption, weight: .semibold))
                Text(err)
                    .font(BsTypography.caption)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    Haptic.light()
                    Task { await viewModel.punch() }
                } label: {
                    Text("重试")
                        .font(BsTypography.captionSmall.weight(.semibold))
                        .foregroundStyle(BsColor.brandAzure)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(BsColor.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func errorIcon(for message: String) -> String {
        if message.contains("定位") || message.contains("位置") || message.contains("围栏") {
            return "location.slash"
        }
        if message.contains("网络") || message.contains("超时") || message.contains("连接") {
            return "wifi.exclamationmark"
        }
        return "exclamationmark.triangle.fill"
    }

    // MARK: - Summary grid (上班 / 下班 / 工时 / 状态)

    private var summaryGrid: some View {
        VStack(alignment: .leading, spacing: BsSpacing.sm + 2) {
            HStack(spacing: BsSpacing.sm) {
                summaryCell(label: "上班", value: Self.fmtTime(viewModel.today?.clockIn))
                summaryCell(label: "下班", value: Self.fmtTime(viewModel.today?.clockOut))
                summaryCell(label: "工时", value: Self.fmtHours(viewModel.today?.workHours))
                statusSummaryCell
            }

            // Secondary row for work_hours + field_work indicator. Kept
            // lightweight so it doesn't disrupt the 4-col grid above.
            if viewModel.today != nil {
                HStack(spacing: BsSpacing.sm) {
                    if let hours = viewModel.today?.workHours {
                        Text("工时: \(Self.fmtHoursInline(hours))")
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }
                    if viewModel.today?.isFieldWork == true {
                        StatusChip(label: "外勤", tone: .blue, icon: "location.fill")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var statusSummaryCell: some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            Text("状态")
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
                .textCase(.uppercase)
            StatusChip.attendance(status: viewModel.today?.status)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BsSpacing.sm + 2)
        // Fusion glass stat tile —— 对齐 Dashboard widget vocabulary
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
        )
    }

    private func summaryCell(label: String, value: String, tone: Color = BsColor.ink) -> some View {
        VStack(alignment: .leading, spacing: BsSpacing.xs) {
            Text(label)
                .font(BsTypography.captionSmall)
                .foregroundStyle(BsColor.inkMuted)
                .textCase(.uppercase)
            Text(value)
                .font(Font.custom("Outfit-Bold", size: 14, relativeTo: .subheadline))
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BsSpacing.sm + 2)
        // Fusion glass stat tile —— 对齐 Dashboard widget vocabulary
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: BsRadius.md, style: .continuous)
        )
    }

    // MARK: - Fence tone/label

    private var fenceLabel: String {
        switch viewModel.fenceState {
        case .idle: return viewModel.hasLocation ? "可打卡" : "等待定位"
        case .acquiring: return "正在获取位置…"
        case .inFence: return "已在围栏内"
        case .outOfFence: return "围栏外，请靠近"
        case .error: return "定位或网络失败"
        }
    }

    private var fenceTone: Color {
        switch viewModel.fenceState {
        case .idle: return viewModel.hasLocation ? BsColor.brandAzure : BsColor.warning
        case .acquiring: return BsColor.brandAzure
        case .inFence: return BsColor.success
        case .outOfFence: return BsColor.warning
        case .error: return BsColor.danger
        }
    }

    // MARK: - Formatting helpers

    private static func fmtTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private static func fmtHours(_ h: Double?) -> String {
        guard let h else { return "—" }
        // 极端值保护：负数 / NaN / 超过 24h 都按合理上限回退
        guard h.isFinite, h >= 0 else { return "—" }
        let clamped = min(h, 99.9)
        let whole = Int(clamped)
        let mins = Int(round((clamped - Double(whole)) * 60))
        // round up 导致 mins == 60 时的进位
        if mins == 60 { return "\(whole + 1)h0m" }
        return "\(whole)h\(mins)m"
    }

    /// Inline variant used in the secondary row, e.g. `工时: 8.5h`.
    private static func fmtHoursInline(_ h: Double) -> String {
        String(format: "%.1fh", h)
    }
}
