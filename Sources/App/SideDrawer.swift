import SwiftUI
import UIKit

/// The animation for opening and closing the drawer; the shell's own toggles use it too.
func drawerAnimation(reduceMotion: Bool) -> Animation {
    reduceMotion ? .easeInOut(duration: 0.2) : .snappy
}

/// A slide-out drawer like the ChatGPT app's: the content is a rounded card that is pushed to the
/// right over a sidebar. iOS has no native phone drawer, so this container is custom; everything
/// inside it is native SwiftUI. It ignores only the `.container` safe area, never the keyboard's,
/// so a composer inside the card still rises with the keyboard.
struct SideDrawer<Sidebar: View, Content: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var content: () -> Content

    @GestureState private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private let maxDrawerWidth: CGFloat = 360
    private let edgeGrabWidth: CGFloat = 28
    private let openCornerRadius: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let drawerWidth = min(geo.size.width * 0.78, maxDrawerWidth)
            let base: CGFloat = isOpen ? drawerWidth : 0
            let offset = min(max(base + drag, 0), drawerWidth)
            let progress = drawerWidth > 0 ? offset / drawerWidth : 0

            ZStack(alignment: .leading) {
                sidebar()
                    .frame(width: drawerWidth)
                    .frame(maxHeight: .infinity)
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
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius(progress), style: .continuous))
                    // After the clip, so the outline survives it. `strokeBorder` draws inside the shape.
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius(progress), style: .continuous)
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
            .simultaneousGesture(dragGesture(drawerWidth: drawerWidth, base: base))
            .accessibilityAction(.escape) { setOpen(false) }
        }
        .ignoresSafeArea(.container)
        .onChange(of: isOpen) { _, nowOpen in
            if nowOpen { dismissKeyboard() }
        }
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

    private func cornerRadius(_ progress: CGFloat) -> CGFloat {
        if reduceMotion { return progress > 0 ? openCornerRadius : 0 }
        return openCornerRadius * min(progress * 4, 1)
    }

    /// One horizontal-dominant drag. Closed, it only starts at the left edge; open, it starts anywhere.
    private func dragGesture(drawerWidth: CGFloat, base: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drag) { value, state, _ in
                // Reset, never return early: a drag that turns vertical after starting horizontal would
                // otherwise leave the card parked at the offset of its last horizontal sample.
                guard isHorizontal(value.translation), canStart(at: value.startLocation) else {
                    state = 0
                    return
                }
                state = value.translation.width
            }
            .onEnded { value in
                guard isHorizontal(value.translation), canStart(at: value.startLocation) else { return }
                setOpen(base + value.predictedEndTranslation.width > drawerWidth / 2)
            }
    }

    private func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height)
    }

    private func canStart(at location: CGPoint) -> Bool {
        isOpen || location.x < edgeGrabWidth
    }

    private func setOpen(_ open: Bool) {
        withAnimation(drawerAnimation(reduceMotion: reduceMotion)) { isOpen = open }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
