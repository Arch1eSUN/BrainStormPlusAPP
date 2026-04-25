import SwiftUI

// ══════════════════════════════════════════════════════════════════
// Iter 6 §A.7 — sheet 一致性升级
//
// iOS 26 polished feel = `.thinMaterial` background + drag indicator.
// Three reusable styles cover the bulk of sheet callsites in the app:
//
//   • `.bsSheetStyle()`        — default detail/preview sheet
//                                 (medium + large detents, drag indicator,
//                                  thinMaterial background).
//   • `.bsSheetStyle(.form)`   — full-height form sheet (CreateTask /
//                                 ProjectCreate / etc). Large only;
//                                 thinMaterial + drag indicator stay.
//   • `.bsSheetStyle(.preview(fraction))` — half-height preview sheet
//                                            (UserPreviewSheet, DayPeek,
//                                            MentionPicker). Custom fraction
//                                            detent + large; thinMaterial +
//                                            drag indicator stay.
//
// These are intentionally NOT in `Shared/DesignSystem/` — that subtree is
// off-limits for Iter 6 polish work. This file is a thin presentation-only
// helper, not a tokenized DS primitive.
// ══════════════════════════════════════════════════════════════════

public enum BsSheetStyle {
    /// Default detail/preview sheet — `[.medium, .large]` detents.
    case detail
    /// Full-height form sheet — `.large` only (forms need vertical room).
    case form
    /// Half-height preview sheet — custom fraction + large.
    case preview(fraction: CGFloat)
}

public extension View {
    /// Apply iOS 26 standard sheet presentation style.
    /// thinMaterial background + drag indicator + appropriate detents.
    @ViewBuilder
    func bsSheetStyle(_ style: BsSheetStyle = .detail) -> some View {
        switch style {
        case .detail:
            self
                .presentationDetents([.medium, .large])
                .presentationBackground(.thinMaterial)
                .presentationDragIndicator(.visible)
        case .form:
            self
                .presentationDetents([.large])
                .presentationBackground(.thinMaterial)
                .presentationDragIndicator(.visible)
        case .preview(let fraction):
            self
                .presentationDetents([.fraction(fraction), .large])
                .presentationBackground(.thinMaterial)
                .presentationDragIndicator(.visible)
        }
    }
}
