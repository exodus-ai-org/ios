import SwiftUI
import UIKit

/// The text view a settled text stands in. A long press selects a word, the handles extend the range, and the
/// system's menu copies it — what `Text` with a custom renderer cannot offer.
final class MarkdownTextView: UITextView {
    /// The rules of the quotes in the text, each drawn beside the lines it stands for.
    var quoteRules: [MarkdownQuoteRule] = [] {
        didSet { if quoteRules != oldValue { setNeedsLayout() } }
    }
    private var ruleViews: [UIView] = []

    /// Set by TextKit 2, as a text view made with no container is. Not `init(usingTextLayoutManager:)`: that is a
    /// class factory, and leaves the properties of a subclass unmade.
    init() {
        super.init(frame: .zero, textContainer: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("made in code")
    }

    /// A selection is copied as its words: a chip among them is a picture, and is left out.
    override func copy(_ sender: Any?) {
        let range = selectedRange
        guard range.length > 0 else { return }
        UIPasteboard.general.string = MarkdownAttributedText.copied(from: attributedText, in: range)
    }

    /// Select All takes every block the text view holds, as long as there is more to take.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(selectAll(_:)) { return selectedRange.length < attributedText.length }
        return super.canPerformAction(action, withSender: sender)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layOutQuoteRules()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        for view in ruleViews { view.backgroundColor = tintColor.withAlphaComponent(0.55) }
    }

    private func layOutQuoteRules() {
        while ruleViews.count > quoteRules.count { ruleViews.removeLast().removeFromSuperview() }
        while ruleViews.count < quoteRules.count {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.backgroundColor = tintColor.withAlphaComponent(0.55)
            view.layer.cornerRadius = MarkdownQuoteRule.width / 2
            insertSubview(view, at: 0)
            ruleViews.append(view)
        }
        guard !quoteRules.isEmpty, let manager = textLayoutManager else { return }
        let lines = MarkdownTextMeasure.lines(in: manager)
        for (rule, view) in zip(quoteRules, ruleViews) {
            let spanned = lines.filter { NSIntersectionRange($0.range, rule.range).length > 0 }
            guard let top = spanned.first?.top, let bottom = spanned.last?.bottom else {
                view.frame = .zero
                continue
            }
            view.frame = CGRect(
                x: rule.x, y: top + MarkdownQuoteRule.inset, width: MarkdownQuoteRule.width,
                height: max(bottom - top - 2 * MarkdownQuoteRule.inset, 0))
        }
    }
}

/// Holds the text view where `Text` would draw the text. SwiftUI places the view it is given; what stands in it
/// is placed here, raised by `lift`.
final class MarkdownTextHolder: UIView {
    let textView: MarkdownTextView
    /// The text as it is set at a width, where that differs by width (`MarkdownRunSnap`).
    var textAtWidth: ((CGFloat) -> NSAttributedString)? {
        didSet { setNeedsLayout() }
    }
    private var setAtWidth: (width: CGFloat, text: NSAttributedString)?
    var lift: CGFloat = 0 {
        didSet { if lift != oldValue { setNeedsLayout() } }
    }

    init(textView: MarkdownTextView) {
        self.textView = textView
        super.init(frame: .zero)
        backgroundColor = .clear
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("made in code")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frame = CGRect(x: 0, y: -lift, width: bounds.width, height: bounds.height + lift)
        if textView.frame != frame { textView.frame = frame }
        if let textAtWidth, bounds.width > 0 {
            let text = textAtWidth(bounds.width)
            if setAtWidth?.width != bounds.width || setAtWidth?.text !== text {
                setAtWidth = (bounds.width, text)
                textView.attributedText = text
                textView.setNeedsLayout()
            }
        } else {
            setAtWidth = nil
        }
    }

    /// The text reaches a pixel above the holder where it is raised: a touch there is the text's.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: 0, dy: -lift).contains(point)
    }
}

/// Where a text's lines stand, for whoever lays the text out beside something else: a text view tells SwiftUI
/// its size and nothing of its lines.
@MainActor
final class MarkdownTextBaselines {
    var first: CGFloat?
    var last: CGFloat?
}

/// A text as a text view sets it at one width: how large it is, and where its first and last lines stand.
struct MarkdownTextMeasurement: Equatable {
    var size: CGSize
    var firstBaseline: CGFloat
    var lastBaseline: CGFloat

    /// As `Text` tells it to a layout: the size up to whole pixels, the baselines to the nearest.
    func reported(scale: CGFloat, within width: CGFloat) -> MarkdownTextMeasurement {
        MarkdownTextMeasurement(
            size: CGSize(
                width: min(MarkdownTextMeasure.pixels(size.width, scale: scale, .up), width),
                height: MarkdownTextMeasure.pixels(size.height, scale: scale, .up)),
            firstBaseline: MarkdownTextMeasure.pixels(firstBaseline, scale: scale, .toNearestOrAwayFromZero),
            lastBaseline: MarkdownTextMeasure.pixels(lastBaseline, scale: scale, .toNearestOrAwayFromZero))
    }

    /// What the text is raised by in a text view, to stand where `Text` draws it. `Text` puts the first baseline
    /// on the nearest pixel, a text view on the next one down: where those are not the same pixel, the glyphs
    /// would stand a pixel lower once a block settles.
    func lift(scale: CGFloat) -> CGFloat {
        MarkdownTextMeasure.pixels(firstBaseline, scale: scale, .up)
            - MarkdownTextMeasure.pixels(firstBaseline, scale: scale, .toNearestOrAwayFromZero)
    }
}

/// Measures a text as a text view sets it, without one.
@MainActor
enum MarkdownTextMeasure {
    private static let storage = NSTextContentStorage()
    private static let container: NSTextContainer = {
        let container = NSTextContainer(size: .zero)
        container.lineFragmentPadding = 0
        return container
    }()
    private static let manager: NSTextLayoutManager = {
        let manager = NSTextLayoutManager()
        manager.textContainer = container
        storage.addTextLayoutManager(manager)
        return manager
    }()

    nonisolated static func pixels(_ value: CGFloat, scale: CGFloat, _ rule: FloatingPointRoundingRule) -> CGFloat {
        let scale = max(scale, 1)
        // A value that is a whole pixel but for what arithmetic left over stays that pixel.
        return ((value * scale * 1024).rounded() / 1024).rounded(rule) / scale
    }

    static func measure(_ text: NSAttributedString, width: CGFloat) -> MarkdownTextMeasurement? {
        guard text.length > 0 else { return nil }
        storage.attributedString = text
        defer { storage.attributedString = nil }
        container.size = CGSize(width: min(width, widest), height: 0)
        var first: CGFloat?
        var last: CGFloat = 0
        var size = CGSize.zero
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            for line in fragment.textLineFragments {
                let bounds = line.typographicBounds
                let baseline = frame.minY + bounds.minY + line.glyphOrigin.y
                if first == nil { first = baseline }
                last = baseline
                // As wide as its widest line, wherever the paragraph's alignment put that line in the room
                // it was given: text set to the right of a wide room is no wider for it.
                size.width = max(size.width, bounds.width)
                size.height = max(size.height, frame.minY + bounds.maxY)
            }
            return true
        }
        guard let first else { return nil }
        return MarkdownTextMeasurement(size: size, firstBaseline: first, lastBaseline: last)
    }

    /// Where each line of a laid out text stands: its characters, the top and bottom of its letters, and where it
    /// starts.
    struct Line: Equatable {
        var range: NSRange
        var top: CGFloat
        var bottom: CGFloat
        var baseline: CGFloat
        var x: CGFloat
    }

    static func lines(in manager: NSTextLayoutManager) -> [Line] {
        guard let content = manager.textContentManager else { return [] }
        let start = manager.documentRange.location
        var lines: [Line] = []
        manager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let offset = content.offset(from: start, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments {
                let bounds = line.typographicBounds
                lines.append(
                    Line(
                        range: NSRange(location: offset + line.characterRange.location, length: line.characterRange.length),
                        top: frame.minY + bounds.minY, bottom: frame.minY + bounds.maxY,
                        baseline: frame.minY + bounds.minY + line.glyphOrigin.y, x: frame.minX + bounds.minX))
            }
            return true
        }
        return lines
    }

    /// `lines(in:)` of a text set at `width`, without a text view.
    static func lines(of text: NSAttributedString, width: CGFloat) -> [Line] {
        storage.attributedString = text
        defer { storage.attributedString = nil }
        container.size = CGSize(width: width, height: 0)
        return lines(in: manager)
    }

    /// The widest a text is set when it is asked how wide it would be with all the room there is.
    nonisolated static let widest: CGFloat = 100_000
}

/// What a tap on something in the text opens: a link's address, or a chip's citation.
enum MarkdownTextTap {
    static func url(of content: UITextItem.Content) -> URL? {
        switch content {
        case .link(let url): url
        case .textAttachment(let attachment): (attachment as? MarkdownChipAttachment)?.chip.link
        default: nil
        }
    }

    /// A long press on a web link offers the system's menu for it; a chip has none.
    static func offersMenu(for url: URL) -> Bool {
        if case .open = MarkdownLinkPolicy.action(for: url) { return true }
        return false
    }
}

/// Text in a text view that is as large as its text: not edited, not scrolled, selected by the word. Links and
/// chips are taps, handed to the `openURL` of where the text stands.
struct SelectableText: UIViewRepresentable {
    let text: NSAttributedString
    var baselines: MarkdownTextBaselines?
    var quotes: [MarkdownQuoteRule] = []
    /// As wide as it is offered, not as its widest line: lines set in from the edge (a list's, a quote's) are
    /// measured without the room before them, and a text view that narrow would break them sooner.
    var fillsWidth = false
    /// Its blocks are moved to where they stood one under another, at the width it is laid out at.
    var snapsBlocks = false

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var shown: NSAttributedString?
        var openURL: OpenURLAction?
        var askAbout: MarkdownAskAction?
        var measured: [CGFloat: MarkdownTextMeasurement] = [:]
        var snapped: [CGFloat: NSAttributedString] = [:]

        /// The text as it is set at `width`: as given, or with its blocks snapped.
        func text(at width: CGFloat, scale: CGFloat, snaps: Bool) -> NSAttributedString? {
            guard let shown else { return nil }
            guard snaps else { return shown }
            if let text = snapped[width] { return text }
            let text = MarkdownRunSnap.snapped(shown, width: width, scale: scale)
            snapped[width] = text
            return text
        }

        func textView(
            _ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction
        ) -> UIAction? {
            guard let url = MarkdownTextTap.url(of: textItem.content) else { return nil }
            return UIAction { [weak self] _ in self?.openURL?(url) }
        }

        func textView(
            _ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu
        ) -> UITextItem.MenuConfiguration? {
            guard let url = MarkdownTextTap.url(of: textItem.content), MarkdownTextTap.offersMenu(for: url) else {
                return nil
            }
            // No preview: it would load the page for a long press.
            return UITextItem.MenuConfiguration(preview: nil, menu: defaultMenu)
        }

        /// A selection's menu leads with "Ask Exodus" where the text can be asked about: the words selected, chips
        /// left out as Copy leaves them, go to the composer as a quote.
        func textView(
            _ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let askAbout, range.length > 0 else { return nil }
            let ask = UIAction(
                title: String(
                    localized: "ios:chat.ask.button", defaultValue: "Ask Exodus",
                    comment: "First item of the menu over text selected in a message: asks a question about it."),
                image: UIImage(systemName: "arrow.turn.down.right")
            ) { [weak textView] _ in
                guard let textView else { return }
                let words = MarkdownAttributedText.copied(from: textView.attributedText, in: range)
                textView.selectedRange = NSRange(location: 0, length: 0)
                askAbout.perform(words)
            }
            return UIMenu(children: [ask] + suggestedActions)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MarkdownTextHolder {
        let view = MarkdownTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        // Every line is set, whatever the view's height: a view a hair shorter than its text must not lose
        // its last line.
        view.textContainer.heightTracksTextView = false
        view.textContainer.size.height = 0
        view.backgroundColor = .clear
        view.adjustsFontForContentSizeCategory = true
        // What is a link is decided where the text is made; nothing is detected in it.
        view.dataDetectorTypes = []
        view.clipsToBounds = false
        view.delegate = context.coordinator
        return MarkdownTextHolder(textView: view)
    }

    func updateUIView(_ holder: MarkdownTextHolder, context: Context) {
        let coordinator = context.coordinator
        coordinator.openURL = context.environment.openURL
        coordinator.askAbout = context.environment.markdownAskAbout
        holder.textView.quoteRules = quotes
        if let shown = coordinator.shown, shown === text || shown.isEqual(to: text) { return }
        coordinator.shown = text
        coordinator.measured.removeAll()
        coordinator.snapped.removeAll()
        if snapsBlocks {
            let scale = context.environment.displayScale
            holder.textAtWidth = { [weak coordinator] width in
                coordinator?.text(at: width, scale: scale, snaps: true) ?? text
            }
        } else {
            holder.textAtWidth = nil
            holder.textView.attributedText = text
            holder.textView.setNeedsLayout()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView holder: MarkdownTextHolder, context: Context) -> CGSize? {
        let coordinator = context.coordinator
        let proposed = proposal.width ?? .infinity
        let width = proposed.isFinite ? max(proposed, 0) : CGFloat.greatestFiniteMagnitude
        // Asked how narrow it can be: as narrow as is wanted, one line tall. Nothing is laid out that narrow.
        guard width >= 1 else { return CGSize(width: 0, height: ceil(holder.textView.font?.lineHeight ?? 0)) }

        let scale = context.environment.displayScale
        if coordinator.measured[width] == nil {
            let set = coordinator.text(at: width, scale: scale, snaps: snapsBlocks) ?? text
            coordinator.measured[width] = MarkdownTextMeasure.measure(set, width: width)
        }
        guard let measured = coordinator.measured[width] else { return .zero }
        let reported = measured.reported(scale: scale, within: width)
        if let baselines {
            baselines.first = reported.firstBaseline
            baselines.last = reported.lastBaseline
        }
        holder.lift = measured.lift(scale: scale)
        if fillsWidth, proposed.isFinite { return CGSize(width: width, height: reported.size.height) }
        return reported.size
    }
}

/// A site's icon to load for a chip, and what is tried when it does not answer.
struct MarkdownIconRequest: Hashable {
    let url: URL
    let fallback: URL?
}

extension MarkdownInlineStyler.Output {
    /// The icons of the text's chips, each once.
    var iconRequests: [MarkdownIconRequest] {
        var seen: Set<URL> = []
        return segments.compactMap { segment in
            guard case .chip(let chip) = segment, let url = chip.iconURL, seen.insert(url).inserted else { return nil }
            return MarkdownIconRequest(url: url, fallback: chip.iconFallbackURL)
        }
    }
}

/// Keeps the text that was made for a view until what it is made from changes: a text made again is another
/// text to a text view, and a selection in it would be lost.
@MainActor
final class MarkdownTextMemo {
    struct Key: Equatable {
        let styled: MarkdownInlineStyler.Output
        let style: MarkdownTextStyle
        let pointSize: CGFloat
        let icons: [URL: ObjectIdentifier]
    }

    private var key: Key?
    private var text = NSAttributedString()

    func text(for key: Key, make: () -> NSAttributedString) -> NSAttributedString {
        if key != self.key {
            self.key = key
            text = make()
        }
        return text
    }
}

/// A settled block's inline content in a text view: the text and chips of `MarkdownStyledText`, where it put
/// them, and a word of it can be selected.
struct MarkdownSelectableText: View {
    let styled: MarkdownInlineStyler.Output
    let spec: MarkdownFontSpec
    var isSecondary = false

    @State private var icons: [URL: UIImage] = [:]
    @State private var memo = MarkdownTextMemo()
    @State private var baselines = MarkdownTextBaselines()
    @Environment(\.markdownCitationIcons) private var loader
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.multilineTextAlignment) private var alignment
    @Environment(\.layoutDirection) private var direction
    @Environment(\.fontResolutionContext) private var fonts
    @Environment(\.markdownLineSpacingScale) private var lineSpacingScale
    @ScaledMetric(relativeTo: .caption2) private var scaledLabelSize = MarkdownChipMetrics.labelSize

    private var style: MarkdownTextStyle {
        var style = MarkdownTextStyle(
            spec: spec, color: isSecondary ? .secondaryLabel : .label,
            alignment: MarkdownTextStyle.alignment(alignment, in: direction), scaledLabelSize: scaledLabelSize,
            displayScale: displayScale, interfaceStyle: colorScheme == .dark ? .dark : .light, fonts: fonts)
        style.lineSpacingScale = lineSpacingScale
        return style
    }

    private var text: NSAttributedString {
        let style = style
        var shown: [URL: UIImage] = [:]
        for request in styled.iconRequests {
            if case .site(let image) = MarkdownChipIcon.resolve(
                url: request.url, fallback: request.fallback, loaded: icons, cached: loader.cached)
            {
                shown[request.url] = image
            }
        }
        let key = MarkdownTextMemo.Key(
            styled: styled, style: style, pointSize: spec.pointSize, icons: shown.mapValues { ObjectIdentifier($0) })
        return memo.text(for: key) {
            MarkdownAttributedText.build(styled, style: style) { chip in
                chip.iconURL.flatMap { shown[$0] }.map { .site($0) } ?? .standIn
            }
        }
    }

    var body: some View {
        let requests = styled.iconRequests
        let baselines = baselines
        SelectableText(text: text, baselines: baselines)
            .alignmentGuide(.firstTextBaseline) { dimensions in baselines.first ?? dimensions[.bottom] }
            .alignmentGuide(.lastTextBaseline) { dimensions in baselines.last ?? dimensions[.bottom] }
            .task(id: requests) {
                for request in requests where icons[request.url] == nil {
                    guard
                        let image = await MarkdownChipIcon.load(
                            url: request.url, fallback: request.fallback, with: loader)
                    else { continue }
                    icons[request.url] = image
                }
            }
    }
}

extension MarkdownTextStyle {
    static func alignment(_ alignment: TextAlignment, in direction: LayoutDirection) -> NSTextAlignment {
        switch alignment {
        case .leading: .natural
        case .center: .center
        case .trailing: direction == .rightToLeft ? .left : .right
        }
    }
}

/// Text that is not markdown, in the transcript's running text, that a word can be selected in: what the user
/// wrote, a line of raw HTML.
public struct SelectableBodyText: View {
    private let text: String
    private let lineSpacing: CGFloat?
    private let isSecondary: Bool

    @State private var baselines = MarkdownTextBaselines()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.multilineTextAlignment) private var alignment
    @Environment(\.layoutDirection) private var direction
    @Environment(\.fontResolutionContext) private var fonts

    /// `lineSpacing`: the room between two lines, in points; the transcript's own when nil.
    public init(_ text: String, lineSpacing: CGFloat? = nil, isSecondary: Bool = false) {
        self.text = text
        self.lineSpacing = lineSpacing
        self.isSecondary = isSecondary
    }

    public var body: some View {
        // The read is the point: the font below is the system's at this text size.
        _ = dynamicTypeSize
        let baselines = baselines
        let style = MarkdownTextStyle(
            spec: .body, color: isSecondary ? .secondaryLabel : .label,
            alignment: MarkdownTextStyle.alignment(alignment, in: direction), lineSpacing: lineSpacing, fonts: fonts)
        return SelectableText(text: MarkdownAttributedText.plain(text, style: style), baselines: baselines)
            .alignmentGuide(.firstTextBaseline) { dimensions in baselines.first ?? dimensions[.bottom] }
            .alignmentGuide(.lastTextBaseline) { dimensions in baselines.last ?? dimensions[.bottom] }
    }
}
