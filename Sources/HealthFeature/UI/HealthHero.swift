// Sources/HealthFeature/UI/HealthHero.swift
import Models
import OdyKit
import SwiftUI

/// The Health home's named coordinate space; the hero reports where the bindle is in it.
enum HealthCoordinateSpace {
    static let home = "healthHome"
}

/// The home's head: the sky at an hour, and Ody living through it. Drag right to go back through last night — the
/// sky darkens, stars come out, Ody lies on its pillow and sinks deeper in deep sleep; let go and it carries on, or
/// tap "Back to now". Laid out in the prototype's 300 × 236 space and scaled by its width; the top `HeroScene.lift`
/// of that sky runs up under the toolbar, so the title sits just below it.
struct HealthHero: View {
    let day: HealthDay?
    let mood: OdyMood
    let now: Date
    let calendar: Calendar
    /// Pull-to-refresh stretches Ody (1 = rest).
    let stretch: CGFloat
    /// Bumped when a memory lands in the bindle: it bounces.
    let bindleBounce: Int
    /// Where the bindle is, in the home's coordinate space, for the memory card's flight; `.zero` while it is hidden.
    @Binding var bindleAnchor: CGRect

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The scrubbed hour, or `nil` while the hero follows now — so a hero left alone keeps up with the clock.
    @State private var hour: Double?
    @State private var dragStart: Double = 0
    /// The hour on screen, which mid-settle is not `hour`: a drag that catches a thrown scrub picks it up here.
    @State private var live = LiveHour()
    @State private var look: CGVector = .zero
    @State private var yawning = false
    @State private var yawn: Task<Void, Never>?
    @State private var stageTick = 0
    @State private var lastStage: SleepStage?

    private static let spring = Spring(response: 0.3, dampingRatio: 1)

    /// `scrubbedTo` starts the hero at an hour of the scrub instead of now (the gallery's frozen states).
    init(
        day: HealthDay?, mood: OdyMood, now: Date, calendar: Calendar, stretch: CGFloat, bindleBounce: Int,
        bindleAnchor: Binding<CGRect>, scrubbedTo hour: Double? = nil
    ) {
        self.day = day
        self.mood = mood
        self.now = now
        self.calendar = calendar
        self.stretch = stretch
        self.bindleBounce = bindleBounce
        _bindleAnchor = bindleAnchor
        _hour = State(initialValue: hour)
    }

    private var scrub: DayScrub { DayScrub(now: now, calendar: calendar) }
    private var today: Date { calendar.startOfDay(for: now) }
    private var shown: Double { hour ?? scrub.now }
    private var atNow: Bool { Self.isAtNow(hour: shown, scrub: scrub) }

    /// Whether the hero is showing now. Past now is still now: a nudge forward only rubber-bands, and must not read as
    /// a scrub (chip, title, pose, haptic).
    static func isAtNow(hour: Double, scrub: DayScrub) -> Bool { !scrub.isScrubbing(min(hour, scrub.now)) }

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 300
            HeroScene(
                hour: shown, scrub: scrub, mood: mood, night: day?.night, today: today, timeZone: calendar.timeZone,
                scale: s, look: look,
                yawning: yawning, stretch: stretch, bindleBounce: bindleBounce, live: live,
                bindleAnchor: $bindleAnchor, onPoke: poke
            )
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("ios:health.hero.a11y"))
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction { direction in
                let next = direction == .increment ? min(shown + 1, scrub.now) : max(shown - 1, scrub.start)
                hour = scrub.isScrubbing(next) ? next : nil
                noteStage()
            }
            .overlay(alignment: .topTrailing) {
                ZStack {
                    if !atNow {
                        Button {
                            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(Self.spring)) { hour = nil }
                        } label: {
                            Label("ios:health.hero.backToNow", systemImage: "arrow.uturn.forward")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        .transition(.scale(0.8).combined(with: .opacity))
                    }
                }
                .padding(.top, (44 - HeroScene.lift) * s)
                .padding(.trailing, 14)
                .animation(.spring(Self.spring), value: atNow)
            }
            // After the overlay, so a swipe that starts on the chip is a scrub too; a tap on it is still a tap.
            .gesture(
                ScrubPan(
                    onBegin: {
                        dragStart = live.value ?? shown
                        lastStage = HeroPose.stage(at: dragStart, night: day?.night, today: today)
                    },
                    onChange: { t, location in
                        var tx = Transaction()
                        tx.disablesAnimations = true
                        withTransaction(tx) {
                            hour = scrub.hour(from: dragStart, translation: t, width: proxy.size.width)
                            look = CGVector(
                                dx: max(-1, min(1, (location.x - 150 * s) / (150 * s))),
                                dy: max(-1, min(1, (location.y - (150 - HeroScene.lift) * s) / (120 * s))))
                        }
                        noteStage()
                    },
                    onEnd: { t, v in release(translation: t, velocity: v, width: proxy.size.width) }))
        }
        .aspectRatio(300 / (236 - HeroScene.lift), contentMode: .fit)
        .sensoryFeedback(.selection, trigger: stageTick)
        .sensoryFeedback(.selection, trigger: atNow) { _, home in home }
    }

    private var accessibilityValue: String {
        let date = today.addingTimeInterval(shown * 3600)
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = calendar.timeZone
        let settled = min(shown, scrub.now)
        let pose = HeroPose.at(hour: settled, scrub: scrub, mood: mood, night: day?.night, today: today)
        let title = String(localized: HeroScene.title(hour: settled, scrub: scrub, mood: mood, pose: pose))
        return date.formatted(style) + ", " + title
    }

    /// Lets go: the scrub carries on with the finger's momentum and lands in range. The spring takes over at the
    /// finger's speed, so there is no seam between dragging and gliding; landing on now hands the hero back to the
    /// clock.
    private func release(translation: CGFloat, velocity: CGFloat, width: CGFloat) {
        let current = scrub.hour(from: dragStart, translation: translation, width: width)
        let target = scrub.release(at: current, velocity: velocity, width: width, reduceMotion: reduceMotion)
        let animation: Animation
        if reduceMotion {
            animation = .easeInOut(duration: 0.2)
        } else {
            let hoursPerSecond = width > 0 ? -Double(velocity / width) * DayScrub.hoursPerWidth : 0
            let distance = target - current
            // A fraction of the distance left per second; capped well below the spring's own stiffness, so a hard
            // throw into either end of the range lands without overshooting it.
            let initial = abs(distance) > 0.01 ? min(max(hoursPerSecond / distance, 0), 10) : 0
            animation = .interpolatingSpring(Self.spring, initialVelocity: initial)
        }
        withAnimation(animation) {
            hour = scrub.isScrubbing(target) ? target : nil
            look = .zero
        }
    }

    private func noteStage() {
        let stage = HeroPose.stage(at: shown, night: day?.night, today: today)
        if stage != lastStage {
            lastStage = stage
            stageTick += 1
        }
    }

    private func poke() {
        guard mood == .tired, atNow, !reduceMotion else { return }
        yawning = true
        // A poke mid-yawn starts the yawn over rather than letting the first one cut it short.
        yawn?.cancel()
        yawn = Task {
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            yawning = false
        }
    }
}

/// The hero drawn at an hour. `Animatable` on the hour, so a spring back to now repaints the sky every frame.
private struct HeroScene: View, Animatable {
    /// How much of the prototype's sky is drawn above the hero's frame, under the status bar and toolbar. The
    /// prototype had room for a bar above the title; in the app that room is the toolbar's.
    static let lift: CGFloat = 40

    var hour: Double
    let scrub: DayScrub
    let mood: OdyMood
    let night: SleepNight?
    let today: Date
    let timeZone: TimeZone
    let scale: CGFloat
    let look: CGVector
    let yawning: Bool
    let stretch: CGFloat
    let bindleBounce: Int
    let live: LiveHour
    @Binding var bindleAnchor: CGRect
    let onPoke: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the bindle is drawn; reported as `bindleAnchor` only while it shows (hidden while Ody sleeps).
    @State private var bindleFrame: CGRect = .zero

    nonisolated var animatableData: Double {
        get { hour }
        set { hour = newValue }
    }

    var body: some View {
        let s = scale
        // Every frame of a settle evaluates this body, so this is always the hour the eye last saw.
        let _ = live.value = hour
        // The sky may show a rubber-band past now; Ody and the title never do.
        let settled = min(hour, scrub.now)
        let pose = HeroPose.at(hour: settled, scrub: scrub, mood: mood, night: night, today: today)
        let nightFactor = DaySky.night(atClockHour: hour)
        let settle: Animation? = reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 1)
        let top = Self.lift
        ZStack(alignment: .topLeading) {
            DaySkyView(clockHour: hour)
            // Pillow, under Ody while asleep.
            RoundedRectangle(cornerRadius: 13 * s)
                .fill(.white)
                .stroke(OdyPalette.hex(0xEBDDBA), lineWidth: 2 * s)
                .frame(width: 72 * s, height: 28 * s)
                .rotationEffect(.degrees(-8))
                .placed(x: 62 * s, y: 180 * s)
                .opacity(pose.asleep ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: pose.asleep)
            // The bindle, beside Ody while awake: where remembered things go. Placed by layout, not `offset`, so
            // the frame it reports is where it is drawn.
            Bindle(bounce: bindleBounce)
                .frame(width: 40 * s, height: 68 * s)
                .placed(x: 56 * s, y: 128 * s)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(HealthCoordinateSpace.home)) } action: {
                    bindleFrame = $0
                    bindleAnchor = pose.asleep ? .zero : $0
                }
                .onChange(of: pose.asleep) { _, asleep in bindleAnchor = asleep ? .zero : bindleFrame }
                .opacity(pose.asleep ? 0 : 1)
                .animation(.easeInOut(duration: 0.3), value: pose.asleep)
            OdyView(
                expression: yawning ? .yawn : pose.expression, look: look, tiredness: pose.tiredness,
                stretch: stretch, onPoke: onPoke
            )
            .frame(width: 100 * s * 560 / 624, height: 106 * s * 600 / 660)
            .rotationEffect(.degrees(pose.tilt), anchor: .bottom)
            .offset(y: pose.sink * s)
            .animation(settle, value: pose.tilt)
            .animation(settle, value: pose.sink)
            .placed(x: (100 + 32.0 / 624 * 100) * s, y: (96 + 30.0 / 660 * 106) * s)
            if pose.asleep || pose.tiredness > 0 {
                Zzz(color: OdyPalette.hex(0x8C7BD6))
                    .frame(width: 50 * s, height: 70 * s)
                    .placed(x: 200 * s, y: 56 * s)
                    .opacity(pose.asleep ? 1 : 0.6)
            }
            // Stage track along the bottom: last night's stages, and where the scrub is.
            StageTrack(night: night, today: today, scrub: scrub, hour: hour)
                .frame(width: 268 * s, height: 11 * s)
                .placed(x: 16 * s, y: 219 * s)
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLine)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.6)
                Text(Self.title(hour: settled, scrub: scrub, mood: mood, pose: pose))
                    .font(.title2.weight(.heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(nightFactor > 0.5 ? OdyPalette.hex(0xF4EFFF) : OdyPalette.hex(0x3A2A00))
            // The words share a fixed picture with Ody: the left 60%, above the top of Ody's head. Big type wraps to
            // two lines, then shrinks to fit the box rather than run into Ody. The full title is the hero's
            // accessibility value, at any size.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .frame(maxWidth: 180 * s, maxHeight: 52 * s, alignment: .topLeading)
            .placed(x: 18 * s, y: 46 * s)
        }
        .frame(width: 300 * s, height: 236 * s, alignment: .topLeading)
        .clipped()
        // The hero is the scene less its top `lift`, which runs up under the toolbar.
        .frame(width: 300 * s, height: (236 - top) * s, alignment: .bottom)
        // The sky carries on above that, under the status bar and into a pull's overscroll.
        .background(alignment: .top) {
            DaySky.gradient(atClockHour: hour).top.color
                .frame(height: 1000)
                .offset(y: -999 - top * s)
        }
    }

    private var dateLine: String {
        let date = today.addingTimeInterval(min(max(hour, scrub.start), scrub.now) * 3600)
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().weekday(.abbreviated).hour().minute()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// The day's mood at now; scrubbed, what Ody was doing then.
    static func title(hour: Double, scrub: DayScrub, mood: OdyMood, pose: HeroPose) -> LocalizedStringResource {
        if !scrub.isScrubbing(hour) { return HeroTitle.of(mood) }
        switch pose.stage {
        case .deep: return "ios:health.stage.deep"
        case .core, .unspecified: return "ios:health.stage.core"
        case .rem: return "ios:health.stage.rem"
        case .awake: return "ios:health.stage.awake"
        case nil:
            if hour < 0 { return "ios:health.hero.notAsleepYet" }
            return "ios:health.hero.awake"
        }
    }
}

/// The hero's headline for the day's mood.
enum HeroTitle {
    static func of(_ mood: OdyMood) -> LocalizedStringResource {
        switch mood {
        case .permission: "ios:health.title.permission"
        case .noData: "ios:health.title.noData"
        case .tired: "ios:health.title.tired"
        case .recovering: "ios:health.title.recovering"
        case .active: "ios:health.title.active"
        case .rested: "ios:health.title.rested"
        case .calm: "ios:health.title.calm"
        case .happy: "ios:health.title.happy"
        }
    }
}

/// The hour on screen, written by the scene each frame it draws. Deliberately not observable: it changes every frame
/// of a settle, and only the start of the next drag reads it.
private final class LiveHour {
    var value: Double?
}

extension View {
    /// Places a view in a top-leading `ZStack` by layout, at a point in the hero's space.
    fileprivate func placed(x: CGFloat, y: CGFloat) -> some View {
        alignmentGuide(.leading) { _ in -x }.alignmentGuide(.top) { _ in -y }
    }
}

private struct StageTrack: View {
    let night: SleepNight?
    let today: Date
    let scrub: DayScrub
    let hour: Double

    var body: some View {
        Canvas { context, size in
            let span = scrub.now - scrub.start
            let x = { (h: Double) in CGFloat((min(max(h, scrub.start), scrub.now) - scrub.start) / span) * size.width }
            let bar = CGRect(x: 0, y: size.height / 2 - 2.5, width: size.width, height: 5)
            let rounded = Path(roundedRect: bar, cornerRadius: 2.5)
            context.fill(rounded, with: .color(.black.opacity(0.08)))
            var stages = context
            stages.clip(to: rounded)
            for s in night?.stages ?? [] {
                let a = x(s.start.timeIntervalSince(today) / 3600)
                let b = x(s.end.timeIntervalSince(today) / 3600)
                let color: UInt32 = switch s.stage {
                case .deep: 0x5B4BC4
                case .rem: 0x8C7BD6
                case .awake: 0xFFC9D3
                case .core, .unspecified: 0xB9AEF0
                }
                stages.fill(Path(CGRect(x: a, y: bar.minY, width: max(1, b - a), height: 5)), with: .color(OdyPalette.hex(color)))
            }
            let r = size.height / 2
            let head = CGRect(x: min(max(x(hour), r), size.width - r) - r, y: 0, width: 2 * r, height: 2 * r)
            context.fill(Path(ellipseIn: head), with: .color(.white))
            context.stroke(Path(ellipseIn: head.insetBy(dx: 0.5, dy: 0.5)), with: .color(OdyPalette.hex(0x3A2A00, 0.25)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Ody's bindle: a stick and a red bundle that bounces when something is put in it.
private struct Bindle: View {
    let bounce: Int

    var body: some View {
        Canvas { context, size in
            let k = size.width / 40
            context.scaleBy(x: k, y: k)
            // Drawn 4 pt down from the prototype's origin: the bundle's top knot sits above it.
            context.translateBy(x: 0, y: 4)
            context.stroke(SVGPath.path("M34 62L16 8"), with: .color(OdyPalette.stick), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            context.fill(SVGPath.path("M2 8c0-13 28-13 28 0 0 11-28 11-28 0z"), with: .color(OdyPalette.bindle))
            context.stroke(SVGPath.path("M11 1l5 5 5-5"), with: .color(OdyPalette.bindleDark), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .keyframeAnimator(initialValue: CGFloat(1), trigger: bounce) { view, scale in
            view.scaleEffect(scale, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.4, duration: 0.08)
                SpringKeyframe(1, duration: 0.6, spring: Spring(response: 0.35, dampingRatio: 0.4))
            }
        }
        .sensoryFeedback(.success, trigger: bounce)
        .accessibilityHidden(true)
    }
}

/// Three z's drifting up from a sleeper.
private struct Zzz: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.3 : timeline.date.timeIntervalSinceReferenceDate * 0.5
            Canvas { context, size in
                let k = size.width / 50
                for i in 0..<3 {
                    let phase = (t + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let font = Font.system(size: CGFloat(20 - i * 5) * k, weight: .heavy)
                    var c = context
                    c.opacity = (1 - phase) * (i == 0 ? 1 : 0.7)
                    c.draw(
                        Text(verbatim: "z").font(font).foregroundStyle(color),
                        at: CGPoint(x: (6 + Double(i) * 14 + phase * 10) * k, y: size.height - (8 + Double(i) * 16 + phase * 18) * k))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
