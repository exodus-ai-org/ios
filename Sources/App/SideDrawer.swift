import Synchronization
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
    /// Where the card was when the finger landed. Read from `liveOffset`, not from the model, so a
    /// drag that catches the card mid-settle picks it up where the eye last saw it.
    @State private var dragStart: CGFloat = 0
    /// The card's position on screen, updated every frame it moves.
    @State private var liveOffset = DrawerLiveOffset()
    /// Bumped once each time letting go of the card changes which state it is in. Only the change
    /// matters, never the number.
    @State private var releases = 0
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
                    // Reduce Motion keeps the fade and drops the growing: a zoom is the kind of
                    // movement that setting exists to remove, and a cross-fade says the same thing
                    // without it. The rows are full size from the first moment they can be seen.
                    .opacity(reveal)
                    .scaleEffect(reduceMotion ? 1 : 0.92 + 0.08 * reveal, anchor: .leading)
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
                    .modifier(DrawerCardOffset(offset: offset, live: liveOffset))
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
            // A rotation moves the card without animating it, and an offset that is never
            // interpolated is never sampled: measured on an open drawer turned to landscape, the
            // card went to 360 while the sampler stayed at the portrait width of 313.6, and the
            // next drag picked it up 46 pt from where it was. The width changing is the one moment
            // the card can move behind the sampler's back.
            .onChange(of: drawerWidth) { _, _ in liveOffset.value = offset }
            .gesture(
                DrawerPan(
                    isOpen: isOpen,
                    // The card is picked up where it is on screen, never where the model says it
                    // is heading: grabbing one in mid-flight used to jump it by whatever was left
                    // of the settle.
                    onBegin: { dragStart = liveOffset.value },
                    onChange: { travel in
                        drag = cardOffset(dragStart + travel, drawerWidth: drawerWidth)
                    },
                    onRelease: { travel, velocity in
                        let landed = cardOffset(dragStart + travel, drawerWidth: drawerWidth)
                        let open = DrawerPhysics.endsOpen(
                            offset: landed, velocity: velocity, drawerWidth: drawerWidth)
                        // In the same update as the settle, so the tap on the wrist and the card
                        // starting to move are one event, not two.
                        if open != isOpen { releases += 1 }
                        settle(
                            open: open, from: landed, velocity: velocity, drawerWidth: drawerWidth)
                    },
                    // A cancelled gesture is not a release: there is no velocity to speak of and the
                    // user did not choose this moment, so the card settles by where it stands.
                    onCancel: {
                        guard let pending = drag else { return }
                        settle(
                            open: pending > drawerWidth / 2, from: pending, velocity: 0,
                            drawerWidth: drawerWidth)
                    }
                )
            )
            .accessibilityAction(.escape) { setOpen(false) }
        }
        // The one piece of feedback the drawer gives beyond moving: a light tap when letting go of
        // the card is what changed its state. Not while dragging, where the card under the finger
        // is the feedback; not when it snaps back to where it already was, which is nothing
        // happening; and not on the toolbar button or the scrim, because system buttons are silent.
        // Whether it fires at all is the phone's business, and the drawer reads the same without it.
        .sensoryFeedback(.impact(weight: .light), trigger: releases)
        .ignoresSafeArea(.container)
        .onChange(of: isOpen) { _, nowOpen in
            if nowOpen { dismissKeyboard() }
        }
    }

    /// Where the card is drawn for the offset the finger is asking for. The closed end is a hard
    /// wall — there is nothing to the left of a full-screen card, and drawing one would show a gap
    /// where the screen ends. The open end is soft: the finger may carry on and the card follows
    /// with less and less of the travel, so pulling past the sidebar reads as "there is no more of
    /// this", not as a seized mechanism.
    private func cardOffset(_ wanted: CGFloat, drawerWidth: CGFloat) -> CGFloat {
        DrawerPhysics.resistedOffset(wanted, drawerWidth: drawerWidth)
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
    ///
    /// The spring is handed the speed the finger was going, so there is no seam where the finger
    /// stops driving the card and the animation takes over — the detail that separates a card that
    /// was thrown from one that was merely let go of.
    private func settle(open: Bool, from current: CGFloat, velocity: CGFloat, drawerWidth: CGFloat) {
        let target = open ? drawerWidth : 0
        withAnimation(
            settleAnimation(velocity: velocity, from: current, to: target, drawerWidth: drawerWidth)
        ) {
            isOpen = open
            drag = nil
        }
    }

    /// The settle's animation: the shared spring, given the release velocity as a fraction of the
    /// distance still to travel. Reduce Motion keeps its short ease and takes no velocity — the
    /// point of it is that nothing flies across the screen.
    private func settleAnimation(
        velocity: CGFloat, from current: CGFloat, to target: CGFloat, drawerWidth: CGFloat
    ) -> Animation {
        guard !reduceMotion else { return drawerAnimation(reduceMotion: true) }
        let handoff = DrawerPhysics.handoffVelocity(velocity, at: current, drawerWidth: drawerWidth)
        return .interpolatingSpring(
            drawerSpring,
            initialVelocity: DrawerPhysics.normalisedVelocity(handoff, from: current, to: target))
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
    let onBegin: () -> Void
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
        case .began:
            onBegin()
            onChange(travel)
        case .changed:
            onChange(travel)
        case .ended:
            onRelease(travel, recognizer.releaseVelocity.x)
        case .cancelled, .failed:
            onCancel()
        default:
            break
        }
    }
}

/// Slides the card, and writes down where it is actually drawn while it does.
///
/// The obvious way to read the card's live position — `onGeometryChange` on the offset view — never
/// sees it move: `frame(in:)` reports layout, and `.offset` is a draw-time transform, so the card's
/// reported frame sits at the closed position for the whole of a settle. (Measured: one sample, of
/// zero, across two full open/close animations.) `Animatable` does see it. SwiftUI drives
/// `animatableData` once per frame with the interpolated value, which is by definition the number
/// on screen, and applying the offset here means the value written down and the value drawn can
/// never drift apart.
private struct DrawerCardOffset: ViewModifier, Animatable {
    var offset: CGFloat
    let live: DrawerLiveOffset

    /// `nonisolated` because `Animatable` is: SwiftUI drives this from its own update pass, not from
    /// a main-actor call, and `DrawerLiveOffset` is built to be written from there.
    nonisolated var animatableData: CGFloat {
        get { offset }
        set {
            offset = newValue
            live.value = drawn
        }
    }

    /// Never left of the closed position. The rubber band takes care of the open end, but the
    /// spring's own bounce carries the value a fraction of a point past zero on the way home
    /// (measured: −0.33 pt), and there is nothing to the left of a full-screen card to show for it.
    nonisolated private var drawn: CGFloat { max(0, offset) }

    func body(content: Content) -> some View {
        content.offset(x: drawn)
    }
}

/// Where the card is on screen, as opposed to where the model says it belongs.
///
/// Deliberately not observable: it changes on every frame of a settle, and a view that watched it
/// would re-render the whole drawer sixty times a second for a number only the start of the next
/// gesture ever reads. Deliberately not actor-isolated either, because `Animatable` is not: the
/// mutex is what makes the one `CGFloat` safe to write from SwiftUI's update pass and read from the
/// gesture, and it costs an uncontended lock per frame.
private final class DrawerLiveOffset: Sendable {
    private let storage = Mutex<CGFloat>(0)

    var value: CGFloat {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
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
    private var lastEvent: CFTimeInterval = 0

    /// Everything the finger has done since it landed, hysteresis included.
    var movementSinceTouchDown: CGPoint {
        guard let touchDown, let view else { return .zero }
        let now = location(in: view)
        return CGPoint(x: now.x - touchDown.x, y: now.y - touchDown.y)
    }

    /// The speed to release at — which is not always the speed `velocity(in:)` reports.
    ///
    /// A finger that has stopped moving sends no more events, and the recognizer goes on reporting
    /// the last speed it managed to compute. Measured: a release 599 ms after the last touch event
    /// still claimed 184 pt/s, which projects 92 pt forward — enough, on its own, to throw a drawer
    /// open that the user had deliberately stopped short of the midpoint and then let go of.
    /// `DrawerPhysics.velocityIsFresh` is the window, and says honestly what it can and cannot see.
    var releaseVelocity: CGPoint {
        guard DrawerPhysics.velocityIsFresh(lastEvent: lastEvent, release: CACurrentMediaTime())
        else { return .zero }
        return velocity(in: view)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touchDown == nil, let first = touches.first {
            touchDown = first.location(in: view)
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        lastEvent = CACurrentMediaTime()
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        touchDown = nil
        lastEvent = 0
    }
}
