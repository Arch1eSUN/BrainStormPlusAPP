import SwiftUI

/// Single-day status card driven by `daily_work_state` — replaces the legacy
/// `Schedule` event card. Shows the Chinese state label (with leave_type
/// override for `personal_leave`), the expected shift window, paid/unpaid
/// pill, and the source origin (system / manager / approved request).
public struct DayStateCardView: View {
    public let dws: DailyWorkState?
    public let date: Date

    public init(dws: DailyWorkState?, date: Date) {
        self.dws = dws
        self.date = date
    }

    public var body: some View {
        let stateStr = dws?.state
        let label = WorkStateLabels.label(state: stateStr, leaveType: dws?.leaveType)
        let stateColor = WorkStateColors.color(state: stateStr, expectedStart: dws?.expectedStart)

        HStack(alignment: .top, spacing: 16) {
            // Left color chip
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(stateColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 10) {
                // Title row
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(BsTypography.sectionTitle)
                        .foregroundStyle(BsColor.ink)

                    Spacer()

                    paidPill
                }

                // Shift window
                if let window = shiftWindow {
                    HStack(spacing: BsSpacing.xs + 2) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(BsColor.inkMuted)
                        Text(window)
                            .font(BsTypography.caption)
                            .foregroundStyle(BsColor.inkMuted)

                        if dws?.flexibleHours == true {
                            Text("弹性")
                                .font(BsTypography.captionSmall)
                                .foregroundStyle(BsColor.brandAzure)
                                .padding(.horizontal, BsSpacing.xs + 2)
                                .padding(.vertical, 2)
                                .background(BsColor.brandAzure.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Source / concrete leave-type footer
                HStack(spacing: BsSpacing.sm) {
                    if let src = WorkStateSource.label(dws?.source) {
                        Label(src, systemImage: "tray.fill")
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(BsColor.inkMuted)
                    }

                    if stateStr == "personal_leave",
                       let lt = dws?.leaveType,
                       let mapped = WorkStateLabels.leaveType[lt],
                       mapped != "事假" {
                        Label(mapped, systemImage: "doc.text.fill")
                            .font(BsTypography.captionSmall)
                            .foregroundStyle(stateColor)
                    }
                }
            }
            .padding(BsSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BsColor.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BsRadius.lg, style: .continuous)
                .stroke(BsColor.borderSubtle, lineWidth: 0.5)
        )
    }

    // MARK: - Computed

    private var shiftWindow: String? {
        guard let start = dws?.expectedStart?.prefix(5),
              let end = dws?.expectedEnd?.prefix(5) else { return nil }
        return "\(start) – \(end)"
    }

    @ViewBuilder
    private var paidPill: some View {
        if let isPaid = dws?.isPaid {
            let text = isPaid ? "计薪" : "不计薪"
            let tone: Color = isPaid ? BsColor.success : BsColor.warning
            Text(text)
                .font(BsTypography.label)
                .foregroundStyle(tone)
                .padding(.horizontal, BsSpacing.sm)
                .padding(.vertical, BsSpacing.xs)
                .background(tone.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}
