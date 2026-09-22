import SwiftUI
import UIKit

/// The one spring the drawer moves on, whether a finger or a toolbar button set it going. It is the
/// `.snappy` this file has always used, written out so the release can hand it a velocity:
/// `Spring.snappy` is `Spring(duration: 0.5, bounce: 0.15)`, and `.spring(Spring.snappy)` is exactly
/// what `.snappy` expands to.
private let drawerSpring = Spring.snappy

/// The animation for opening and closing the drawer; the shell's own toggles use it too.
func drawerAnimation(reduceMotion: Bool) -> Animation {
    reduceMotion ? .easeInOut(duration: 0.2) : .spring(drawerSpring)
}

/// A slide-out drawer like the ChatGPT app's: the content is a rounded card that is pushed to the
/// right over a sidebar. iOS has no native phone drawer, so this container is custom; everything
/// inside it is native SwiftUI. It ignores only the `.container` safe area, never the keyboard's,
/// so a composer inside the card still rises with the keyboard.
struct SideDrawer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var content: () -> Content

    /// The card's offset while a drag is in flight, in points from the closed position, or `nil`
    /// when no drag is pending. Ordinary `@State`, deliberately not `@GestureState`: SwiftUI resets
    /// a `@GestureState` *before* the release is handled, so the card rendered one frame at the
    /// closed offset — the release flash — before the new `isOpen` animated it back out.
    @State private var drag: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private let maxDrawerWidth: CGFloat = 360
    /// What the card's corners fall back to on a display that reports square corners.
    private let minCornerRadius: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let drawerWidth = min(geo.size.width * 0.78, maxDrawerWidth)
            let base: CGFloat = isOpen ? drawerWidth : 0
            let offset = drag ?? base
            let progress = drawerWidth > 0 ? min(max(offset / drawerWidth, 0), 1) : 0
            // This reader fills the display, so its concentric radii are the display's own. The
            // card keeps them even while closed: a full-screen card's corners sit under the
            // physical corners of the screen, where they cannot be seen. A square-cornered
            // display reports 0 and only then does the fallback apply — a small radius that was
            // genuinely reported is the display's, and raising it would miss those corners.
            let displayRadius = geo.concentricCornerRadii?.bottomLeading ?? 0
            let cardRadius = displayRadius > 0 ? displayRadius : minCornerRadius
            // How far the sidebar has arrived, 0 … 1. It runs ahead of the card so the sidebar has
            // settled by the time the card lands, and it reaches exactly 1, never a dimmed open state.
            let reveal = min(1, progress * 1.5)

            ZStack(alignment: .leading) {
                sidebar()
                    .frame(width: drawerWidth)
                    .frame(maxHeight: .infinity)
                    // The content fades in and grows into place as the card uncovers it. Anchored at
                    // the leading edge, so rows do not drift sideways while they are being revealed.
                    .opacity(reveal)
                    .scaleEffect(0.92 + 0.08 * reveal, anchor: .leading)
                    // Behind the fade, so the strip the card has uncovered is always solid.
                    .background(Color(.systemBackground))
                    // Closed: invisible, inert and skipped by VoiceOver.
                    .opacity(progress > 0 ? 1 : 0)
                    .allowsHitTesting(isOpen)
                    .accessibilityHidden(!isOpen)

                content()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .background(cardBackground(progress))
                    // Dims the card's content toward the card's own background, never toward black:
                    // in dark mode a plain `systemBackground` scrim would undo the lift below.
                    .overlay {
                        cardBackground(progress)
                            .opacity(0.6 * progress)
                            .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
                    // After the clip, so the outline survives it. `strokeBorder` draws inside the shape.
                    .overlay {
                        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(borderOpacity(progress)), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.15 * progress), radius: 24, x: -4)
                    .offset(x: offset)
                    .accessibilityHidden(isOpen)

                if isOpen {
                    // The tap target over the card: one VoiceOver button that closes the drawer.
                    Color.clear
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .offset(x: offset)
                        .onTapGesture { setOpen(false) }
                        .accessibilityElement()
                        .accessibilityLabel("Close sidebar")
                        .accessibilityAddTraits(.isButton)
                        // `onTapGesture` alone can be dead to a VoiceOver activation of a synthesized
                        // element, so spell the action out.
                        .accessibilityAction { setOpen(false) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .gesture(
                DrawerPan(
                    isOpen: isOpen,
                    onChange: { travel in
                        drag = cardOffset(base + travel, drawerWidth: drawerWidth)
                    },
                    onRelease: { travel, velocity in
                        let landed = cardOffset(base + travel, drawerWidth: drawerWidth)
                        settle(
                            open: DrawerPhysics.endsOpen(
                                offset: landed, velocity: velocity, drawerWidth: drawerWidth))
                    },
                    // A cancelled gesture is not a release: there is no velocity to speak of and the
                    // user did not choose this moment, so the card settles by where it stands.
                    onCancel: {
                        guard let pending = drag else { return }
                        settle(open: pending > drawerWidth / 2)
                    }
                )
            )
            .accessibilityAction(.escape) { setOpen(false) }
        }
        .ignoresSafeArea(.container)
        .onChange(of: isOpen) { _, nowOpen in
            if nowOpen { dismissKeyboard() }
        }
    }

    /// Where the card is drawn for the offset the finger is asking for. The closed end is a hard
    /// wall — there is nothing to the left of a full-screen card — and so, for now, is the open one.
    private func cardOffset(_ wanted: CGFloat, drawerWidth: CGFloat) -> CGFloat {
        min(max(wanted, 0), drawerWidth)
    }

    /// The hairline that separates the card from the sidebar, white and barely there. Dark mode only:
    /// in light mode a white card over a white sidebar is already told apart by its shadow.
    private func borderOpacity(_ progress: CGFloat) -> CGFloat {
        colorScheme == .dark ? 0.15 * progress : 0
    }

    /// The card's own background. Closed it is exactly `systemBackground`, so the chat screen and its
    /// bubbles look as they always did; as the drawer opens, dark mode lifts it toward
    /// `secondarySystemBackground` so the card reads as a layer above the (still black) sidebar. Light
    /// mode keeps its white card and its shadow.
    private func cardBackground(_ progress: CGFloat) -> some View {
        ZStack {
            Color(.systemBackground)
            if colorScheme == .dark {
                Color(.secondarySystemBackground).opacity(progress)
            }
        }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(drawerAnimation(reduceMotion: reduceMotion)) { isOpen = open }
    }

    /// Ends a drag: the new resting place and the end of the drag are one change, so the card
    /// animates straight from the offset on screen to the target with no frame in between.
    private func settle(open: Bool) {
        withAnimation(drawerAnimation(reduceMotion: reduceMotion)) {
            isOpen = open
            drag = nil
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// The drawer's drag: a UIKit pan recognizer, behind SwiftUI.
///
/// SwiftUI's own `DragGesture` cannot do this job. It has no way to say "this touch is not mine" —
/// it either wins the touch or runs alongside whatever else claims it — so the old gesture had to
/// buy its exclusivity with a 28 pt strip at the left edge, which is the restriction this replaces.
/// UIKit arbitrates properly, and for free:
///
/// * `gestureRecognizerShouldBegin` decides intent ONCE, from the translation the pan has already
///   accumulated (about 10 pt of hysteresis, and a slow drag has it just as a fast one does). A
///   drag that began horizontal stays the drawer's however the finger wanders afterwards; a drag
///   that began vertical never becomes the drawer's.
/// * A scroll view does not begin its own pan for a horizontal start it cannot act on, and this pan
///   refuses a vertical one, so the transcript and the drawer never fight over a touch.
/// * Two recognizers are mutually exclusive unless a delegate says otherwise, and this one says
///   nothing: the text view's long-press and selection recognizers, having begun first, keep the
///   touch, so dragging a selection cannot open the drawer.
/// * `cancelsTouchesInView` is on by default, so a button under the finger at the start of a swipe
///   is cancelled rather than tapped.
/// * The recognizer reports `.cancelled` honestly when the system takes the touch away, which is
///   what the old code needed a deferred watcher to infer.
private struct DrawerPan: UIGestureRecognizerRepresentable {
    /// Which way a drag has to go to be ours. Refreshed on the recognizer's coordinator at every
    /// update, because `gestureRecognizerShouldBegin` runs on the delegate, not on this struct.
    let isOpen: Bool
    let onChange: (CGFloat) -> Void
    let onRelease: (CGFloat, CGFloat) -> Void
    let onCancel: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isOpen = false

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? DrawerPanRecognizer else { return false }
            let movement = pan.movementSinceTouchDown
            // Judged from the movement, not the velocity: a finger creeping across the screen has a
            // direction to read and barely a velocity, and would lose the drawer to noise.
            guard abs(movement.x) > abs(movement.y) else { return false }
            // Closed there is only rightward to go, open only leftward. The other direction has
            // nothing to show, so the touch is left to whatever is underneath it.
            return isOpen ? movement.x < 0 : movement.x > 0
        }

        // Nothing else is implemented on purpose. `shouldRecognizeSimultaneouslyWith` stays at its
        // default of false, which is what leaves the text view's selection recognizers — already
        // begun, and therefore already the winners — holding a selection drag. And the scroll views
        // need no failure requirement from this side: a scroll view that can only scroll vertically
        // declines a horizontal-dominant start of its own accord, so the two never both want the
        // same touch. Measured, not assumed: with a forty-turn transcript under the finger, a
        // horizontal drag opens the drawer without scrolling the transcript, and a vertical one
        // scrolls the transcript without moving the card.
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> DrawerPanRecognizer {
        let pan = DrawerPanRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: DrawerPanRecognizer, context: Context) {
        context.coordinator.isOpen = isOpen
    }

    func handleUIGestureRecognizerAction(_ recognizer: DrawerPanRecognizer, context: Context) {
        // `translation` has UIKit's ~10 pt of hysteresis already taken out of it, so the card is
        // still at the closed offset when the pan begins and moves point for point with the finger
        // from there: a real drawer has that much slack in its runners, and it is what keeps a tap
        // or a scroll from nudging the card. It never jumps to catch the finger up.
        let travel = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChange(travel)
        case .ended:
            onRelease(travel, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onCancel()
        default:
            break
        }
    }
}

/// A pan that also remembers where the finger landed.
///
/// `translation(in:)` has UIKit's hysteresis subtracted from it, so at the moment the recognizer
/// must decide whose gesture this is there is barely a point of it to read — mostly noise on a real
/// finger. The movement since touch-down is the whole ten points, and a direction judged from ten
/// points is a direction, not a wobble.
private final class DrawerPanRecognizer: UIPanGestureRecognizer {
    private var touchDown: CGPoint?

    /// Everything the finger has done since it landed, hysteresis included.
    var movementSinceTouchDown: CGPoint {
        guard let touchDown, let view else { return .zero }
        let now = location(in: view)
        return CGPoint(x: now.x - touchDown.x, y: now.y - touchDown.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touchDown == nil, let first = touches.first {
            touchDown = first.location(in: view)
        }
        super.touchesBegan(touches, with: event)
    }

    override func reset() {
        super.reset()
        touchDown = nil
    }
}
