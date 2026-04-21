import SwiftUI
import Foundation

/// Sprint 3.5: builds the styled `AttributedString` used to render message
/// bodies and search-result previews. Closes the remaining slice of
/// 3.1-debt-04 (@mentions) by matching Web `page.tsx:31-39 renderContent`:
///
/// ```ts
/// const parts = text.split(/(@\S+)/g)
/// return parts.map(part => part.startsWith('@') ? <span .../> : part)
/// ```
///
/// Web only does the mention pass. iOS bundles a second, optional "search
/// term" highlight pass so the cross-channel search list (Sprint 3.4) can
/// show users *why* a row matched. That second pass has no Web analog —
/// foundation-polish only.
///
/// Two gotchas worth keeping in mind if this ever gets extended:
///
/// 1. `NSRange` offsets are UTF-16, not `Character` indices. Conversion
///    goes via `Range<String.Index>` (which understands UTF-16) and then
///    `raw.distance(...)` to get character offsets compatible with
///    `AttributedString.index(_:offsetByCharacters:)`. Skipping that
///    round-trip breaks on CJK + emoji.
/// 2. Mention color must contrast with the bubble background. Caller
///    supplies `mentionColor` — on self-bubbles (blue background) we pass
///    `.yellow`; on peer bubbles and list rows we pass `.blue`.
public enum ChatContentHighlighter {
    /// Builds the styled body. `searchTerm` is applied as a case-insensitive
    /// literal highlight; `nil` or strings < 2 chars are ignored (mirrors
    /// `searchMessages` min-query length).
    public static func attributed(
        _ raw: String,
        searchTerm: String? = nil,
        mentionColor: Color = .blue,
        matchBackground: Color = Color.yellow.opacity(0.45)
    ) -> AttributedString {
        var attributed = AttributedString(raw)

        applyRegex(#"@\S+"#, on: raw, to: &attributed) { slice in
            slice.font = .body.weight(.semibold)
            slice.foregroundColor = mentionColor
        }

        if let term = searchTerm?.trimmingCharacters(in: .whitespacesAndNewlines),
           term.count >= 2 {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            applyRegex("(?i)\(escaped)", on: raw, to: &attributed) { slice in
                slice.backgroundColor = matchBackground
            }
        }

        return attributed
    }

    // MARK: - Private

    /// Runs `pattern` over `raw` and mutates each matched range on
    /// `attr`. `raw` is the source-of-truth for indices — `attr` must
    /// have been constructed from the same string so character counts
    /// line up.
    private static func applyRegex(
        _ pattern: String,
        on raw: String,
        to attr: inout AttributedString,
        style: (inout AttributedString) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let fullRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        let matches = regex.matches(in: raw, range: fullRange)

        for match in matches {
            guard let strRange = Range(match.range, in: raw) else { continue }
            let startOffset = raw.distance(from: raw.startIndex, to: strRange.lowerBound)
            let length = raw.distance(from: strRange.lowerBound, to: strRange.upperBound)
            let attrStart = attr.index(attr.startIndex, offsetByCharacters: startOffset)
            let attrEnd = attr.index(attrStart, offsetByCharacters: length)
            var slice = AttributedString(attr[attrStart..<attrEnd])
            style(&slice)
            attr.replaceSubrange(attrStart..<attrEnd, with: slice)
        }
    }
}
