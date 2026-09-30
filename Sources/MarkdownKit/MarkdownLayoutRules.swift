import SwiftUI

/// Spacing, heading fonts and list markers, in body-size units ("em") so they follow Dynamic Type.
/// One uniform gap between blocks, a larger lead-in before a heading, a small gap after it, tight spacing
/// inside list items. The measure is a reading one: paragraphs stand a full line apart and the lines of
/// running text about 1.6 em from each other, which is what Chinese and Japanese need to be read at length
/// and does Latin text no harm; a heading's own lines stay close, since they are one thought.
enum MarkdownLayoutRules {
    /// ChatGPT's measure (owner's reference, 2026-09-30): paragraphs 45.5 pt apart baseline to baseline at a 16 pt
    /// body whose lines are 23.5 pt apart.
    static let blockGap: CGFloat = 1.8
    static let listGap: CGFloat = 0.5
    static let afterHeadingGap: CGFloat = 0.6
    static let ruleGap: CGFloat = 1.4

    /// The room added between two lines of one block, as a fraction of its font size.
    static func lineGap(for spec: MarkdownFontSpec) -> CGFloat {
        switch spec.style {
        case .largeTitle, .title, .title2, .title3: 0.16
        case .headline: 0.24
        case .body, .callout: 0.42
        default: 0.34
        }
    }

    static func gap(after previous: MarkdownBlock.Kind?, before next: MarkdownBlock.Kind, inList: Bool) -> CGFloat {
        guard let previous else { return 0 }
        if case .heading(let level, _) = next {
            if inList { return listGap }
            switch level {
            case 1: return 2.3
            case 2: return 2.1
            case 3: return 1.95
            default: return 1.85
            }
        }
        if case .heading = previous { return inList ? listGap : afterHeadingGap }
        if case .thematicBreak = previous { return ruleGap }
        if case .thematicBreak = next { return ruleGap }
        return inList ? listGap : blockGap
    }

    static func headingFont(level: Int) -> MarkdownFontSpec {
        switch level {
        case 1: MarkdownFontSpec(style: .title2, weight: .semibold)
        case 2: MarkdownFontSpec(style: .title3, weight: .semibold)
        case 3: MarkdownFontSpec(style: .headline)
        case 4: MarkdownFontSpec(style: .callout, weight: .semibold)
        default: MarkdownFontSpec(style: .subheadline, weight: .semibold)
        }
    }

    static func listMarker(isOrdered: Bool, number: Int, depth: Int) -> String {
        if isOrdered { return "\(number)." }
        switch depth {
        case 0: return "\u{2022}"
        case 1: return "\u{25E6}"
        default: return "\u{25AA}\u{FE0E}"
        }
    }

    /// The widest marker of a list, laid out hidden so every item's text starts at the same x.
    static func widestMarker(_ list: MarkdownList, depth: Int) -> String {
        guard list.isOrdered, !list.items.isEmpty else {
            return listMarker(isOrdered: list.isOrdered, number: list.startIndex, depth: depth)
        }
        let digits = max(String(list.startIndex).count, String(list.startIndex + list.items.count - 1).count)
        return String(repeating: "0", count: digits) + "."
    }
}
