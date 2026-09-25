import SwiftUI

/// The seam between iOS's static launch screen and the app.
///
/// A launch screen cannot animate, so it only shows Ody's icon on
/// `LaunchBackground` (see `UILaunchScreen` in Project.swift). This overlay
/// starts on that exact frame — same image, same size, centred on the same
/// full-screen background — so the hand-off is invisible, then gives the icon
/// the hop the desktop boot splash has (squash, jump, land) and zooms it away
/// to reveal the app. It never takes touches; with Reduce Motion it only fades.
struct LaunchSplash: ViewModifier {
    /// Must match the launch image's point size (the @2x/@3x assets are 224 and 336 px).
    static let logoSize: CGFloat = 112

    private enum Phase { case resting, squash, hop, land, exit }

    @State private var phase: Phase = .resting
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if !finished {
                ZStack {
                    Color("LaunchBackground")
                    Image("LaunchLogo")
                        .resizable()
                        .frame(width: Self.logoSize, height: Self.logoSize)
                        .scaleEffect(x: stretch.x, y: stretch.y, anchor: .bottom)
                        .offset(y: lift)
                        .scaleEffect(phase == .exit ? 1.35 : 1)
                }
                .ignoresSafeArea()
                .opacity(phase == .exit ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task { await play() }
            }
        }
    }

    /// Squash-and-stretch around the icon's bottom edge, like Ody pushing off.
    private var stretch: (x: CGFloat, y: CGFloat) {
        switch phase {
        case .squash: (1.08, 0.9)
        case .hop: (0.96, 1.05)
        default: (1, 1)
        }
    }

    private var lift: CGFloat { phase == .hop ? -26 : 0 }

    @MainActor
    private func play() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { phase = .exit }
            try? await Task.sleep(for: .milliseconds(250))
            finished = true
            return
        }
        // A beat on the launch frame first, so the motion reads as Ody's, not a glitch.
        try? await Task.sleep(for: .milliseconds(120))
        await step(.squash, .spring(duration: 0.16, bounce: 0), hold: 150)
        await step(.hop, .spring(duration: 0.26, bounce: 0), hold: 230)
        // The landing is the one place with overshoot: the jump carried momentum.
        await step(.land, .spring(duration: 0.36, bounce: 0.4), hold: 240)
        await step(.exit, .spring(duration: 0.34, bounce: 0), hold: 300)
        finished = true
    }

    @MainActor
    private func step(_ next: Phase, _ animation: Animation, hold milliseconds: Int) async {
        withAnimation(animation) { phase = next }
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

extension View {
    /// Covers the view with the launch frame, then animates it away once.
    func launchSplash() -> some View {
        modifier(LaunchSplash())
    }
}
