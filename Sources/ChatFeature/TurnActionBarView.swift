import SwiftUI
import UIKit

/// Copy, Read aloud, Regenerate and Sources, under a finished answer, and when it was written. Equatable on what it shows only: the closures
/// never change what a bar looks like, so a finished turn's bar is not evaluated again while a later reply streams.
/// (What read-aloud is doing is read from its model, which tells this view itself.)
struct TurnActionBarView: View, Equatable {
    nonisolated let bar: TurnActionBar
    let onRegenerate: () -> Void
    let onShowSources: () -> Void

    @State private var copyCount = 0
    #if DEBUG
        /// `-MessageGalleryCopied` draws the bar as it is just after Copy, for screenshots.
        @State private var copied = MessageGalleryLaunch.copied
    #else
        @State private var copied = false
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readAloud) private var readAloud

    nonisolated static func == (lhs: TurnActionBarView, rhs: TurnActionBarView) -> Bool { lhs.bar == rhs.bar }

    var body: some View {
        HStack(spacing: 0) {
            copyButton
            if bar.showsReadAloud, let readAloud {
                ReadAloudButton(bar: bar, model: readAloud)
            }
            if bar.showsRegenerate {
                regenerateButton
            }
            if bar.showsSources {
                sourcesButton
            }
            if let generatedAt = bar.generatedAt {
                GeneratedAtText(date: generatedAt)
            }
            Spacer(minLength: 0)
        }
        // A shade darker than secondary: thin strokes in a pale grey disappear.
        .foregroundStyle(Color(.label).opacity(0.62))
        // Glyphs and one word, not prose: past this size the bar would no longer fit a line, and its targets are already large.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // Each target is its glyph's box and `BarTarget`'s reach around it. The row takes the room of its glyphs
        // only: the targets reach above, below and to the left of it, so the glyphs line up with the answer's text
        // and sit close under it instead of a full target away.
        .padding(.vertical, -BarTarget.reach.height)
        .padding(.leading, -BarTarget.reach.width)
        .sensoryFeedback(.success, trigger: copyCount)
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            // A newer copy cancels this wait; its own task resets the glyph, not this one.
            guard (try? await Task.sleep(for: .seconds(1.5))) != nil else { return }
            copied = false
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = bar.copyText
            copied = true
            copyCount += 1
            AccessibilityNotification.Announcement(Self.copiedAnnouncement).post()
        } label: {
            Label {
                if copied {
                    Text("common:state.copied")
                } else {
                    Text("common:action.copy")
                }
            } icon: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")  // l10n:ignore: SF Symbol names
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .modifier(BarGlyph())
            }
            .labelStyle(.iconOnly)
            .modifier(BarTarget())
        }
        .buttonStyle(.plain)
    }

    private var regenerateButton: some View {
        Button(action: onRegenerate) {
            Label {
                Text("chat:messageAction.regenerate")
            } icon: {
                Image(systemName: "arrow.clockwise").modifier(BarGlyph())
            }
            .labelStyle(.iconOnly)
            .modifier(BarTarget())
        }
        .buttonStyle(.plain)
    }

    /// The desktop's Sources button: the icons of the first sites, overlapping, and the word.
    private var sourcesButton: some View {
        Button(action: onShowSources) {
            HStack(spacing: 6) {
                SourceAvatarGroup(avatars: bar.sourceIcons)
                Text("chat:messageAction.sources")
                    .font(.footnote)
                    .lineLimit(1)
            }
            .modifier(BarTarget())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("chat:messageAction.sources"))
        .accessibilityValue(Text(bar.sourceCount, format: .number))
    }

    private static var copiedAnnouncement: String {
        String(localized: "common:state.copied", defaultValue: "Copied", comment: "Said aloud after the answer was copied.")
    }
}

/// When the answer was written, as the desktop's bar ends: short and faint ("5m ago"), kept current while on screen.
/// VoiceOver hears it in full.
struct GeneratedAtText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(verbatim: Self.short(date, now: context.date))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.leading, 8)
                .accessibilityLabel(Text(date, format: .relative(presentation: .named, unitsStyle: .wide)))
        }
    }

    /// "now" under a minute, then the largest whole unit, abbreviated — the desktop's `compactRelativeTime`, localized.
    static func short(_ date: Date, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .abbreviated
        // Under a minute is "now", as on the desktop, not a count of seconds; and a phone whose clock runs behind
        // the computer's would otherwise read a fresh answer as "in 1m".
        let shown = now.timeIntervalSince(date) < 60 ? now : date
        return formatter.localizedString(for: shown, relativeTo: now)
    }
}

/// Read aloud: a speaker, a spinner while the computer makes the audio, a stop while it plays. It reads where it
/// stands from the chat's model, for its own answer only.
private struct ReadAloudButton: View {
    let bar: TurnActionBar
    let model: ReadAloudModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let phase = model.phase(for: bar.turnId)
        Button {
            Task { await model.toggle(id: bar.turnId, text: bar.speechText) }
        } label: {
            Label {
                if phase == .idle {
                    Text("audio:player.readAloud")
                } else {
                    Text("audio:player.stop")
                }
            } icon: {
                ZStack {
                    // The speaker keeps the glyph's place, so the bar does not move when the spinner comes.
                    Image(systemName: phase == .playing ? "stop.fill" : "speaker.wave.2")  // l10n:ignore: SF Symbol names
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .opacity(phase == .loading ? 0 : 1)
                    if phase == .loading {
                        ProgressView().controlSize(.small)
                    }
                }
                .modifier(BarGlyph())
            }
            .labelStyle(.iconOnly)
            .modifier(BarTarget())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(trigger: phase) { old, new in
            old != .playing && new == .playing ? .start : nil
        }
    }
}

/// Up to three site icons, round and overlapping, each ringed in the page's background so the overlap reads.
private struct SourceAvatarGroup: View {
    let avatars: [SourceAvatar]
    @ScaledMetric(relativeTo: .footnote) private var side: CGFloat = 17

    static let ring: CGFloat = 1.5
    static let overlap: CGFloat = 5

    var body: some View {
        HStack(spacing: -(Self.overlap + Self.ring)) {
            ForEach(Array(avatars.enumerated()), id: \.element.id) { index, avatar in
                SourceAvatarView(avatar: avatar, side: side)
                    .padding(Self.ring)
                    .background(Color(.systemBackground), in: .circle)
                    // The first is on top, as a stack of cards fanned to the right.
                    .zIndex(Double(avatars.count - index))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SourceAvatarView: View {
    let avatar: SourceAvatar
    let side: CGFloat
    @State private var loaded: UIImage?
    @Environment(\.searchMediaLoader) private var loader

    private var image: UIImage? {
        loaded ?? avatar.iconURL.flatMap { loader.cached($0, maxPixelSize: SourceIcon.pixelSize) }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .padding(side * 0.16)
                    .foregroundStyle(.secondary)
                    .background(Color(.secondarySystemFill))
            }
        }
        .frame(width: side, height: side)
        .background(Color(.systemBackground))
        .clipShape(.circle)
        // Sites draw their icons every way — square, bare glyph on transparency, white on white: one hairline
        // round each gives the three the same edge.
        .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
        .task(id: avatar.iconURL) {
            guard let url = avatar.iconURL, image == nil else { return }
            loaded = try? await loader.load(url, maxPixelSize: SourceIcon.pixelSize)
        }
    }
}

/// The box every glyph of the bar is set in. Symbols are not all one width — a checkmark is narrower than the two
/// sheets it stands in for — and a row of boxes does not move when one glyph becomes another.
private struct BarGlyph: ViewModifier {
    @ScaledMetric(relativeTo: .subheadline) private var side: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 14

    func body(content: Content) -> some View {
        // Small, with a firm stroke: small print under an answer that still reads at a glance.
        content
            .font(.system(size: size, weight: .medium))
            .frame(width: side, height: side)
    }
}

/// A touch target around a glyph's box: 44 pt high, and 28 wide so the glyphs of the row stand as a group, about
/// 10 pt apart as ChatGPT's do, instead of a full target from each other.
private struct BarTarget: ViewModifier {
    static let reach = CGSize(width: 5, height: 13)

    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .padding(.horizontal, Self.reach.width)
            .padding(.vertical, Self.reach.height)
            .frame(minWidth: 28, minHeight: 44)
            .contentShape(.rect)
    }
}
