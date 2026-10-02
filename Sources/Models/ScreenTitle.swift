import Foundation
import Observation
import SwiftUI

/// The app's `NSUserActivity` types (also listed under `NSUserActivityTypes` in the Info.plist).
public enum ExodusActivity {
    /// What is on screen, as the system's current activity: iOS titles a screenshot after its `title` (the share
    /// sheet's header, and the file's name when it is AirDropped).
    public static let viewing = "app.yancey.exodus.viewing"
}

/// How a screen's title is put together: its parts, trimmed, the empty ones dropped, joined by a middle dot
/// ("Settings · Memory", "Memories used · Trip to Kyoto").
public enum ScreenTitles {
    public static let separator = " \u{00B7} "

    public static func join(_ parts: String?...) -> String { join(parts) }

    public static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }
}

/// Every titled screen on display, and which one is in front. A screen nested in another (a sheet over the screen
/// that presents it, a page pushed over its stack's root) is deeper; at the same depth the one shown last is in front,
/// so a sheet or a pushed page wins over what is beneath it, and when it goes the title beneath is back.
public struct ScreenTitleStack: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var depth: Int
        var order: Int
        var title: String
    }

    private var entries: [UUID: Entry] = [:]
    private var nextOrder = 0

    public init() {}

    /// A screen appearing (in front of the others at its depth), or a shown screen's title changing (in place).
    public mutating func show(_ id: UUID, depth: Int, title: String) {
        if entries[id] != nil {
            entries[id]?.title = title
        } else {
            entries[id] = Entry(depth: depth, order: nextOrder, title: title)
            nextOrder += 1
        }
    }

    public mutating func hide(_ id: UUID) { entries[id] = nil }

    /// The title of the screen in front, if any screen is titled.
    public var front: String? {
        entries.values.max { ($0.depth, $0.order) < ($1.depth, $1.order) }?.title
    }
}

/// The scene's titled screens, shared through the environment by `publishesScreenTitle()`.
@MainActor @Observable
public final class ScreenTitleRegistry {
    public private(set) var stack = ScreenTitleStack()

    public init() {}

    func show(_ id: UUID, depth: Int, title: String) { stack.show(id, depth: depth, title: title) }
    func hide(_ id: UUID) { stack.hide(id) }
}

extension EnvironmentValues {
    /// The title of the screen this view is in (empty outside any titled screen): what a sheet adds its own name to.
    @Entry public var screenTitle: String = ""
    /// How many titled screens this view is nested in.
    @Entry var screenTitleDepth: Int = 0
}

extension View {
    /// Names what this view shows, for the system: a screenshot taken while it is the frontmost titled screen is
    /// titled after it. A sheet or a pushed page over it wins while it is up; the title comes back when it goes.
    /// Needs `publishesScreenTitle()` above it (the app's root); without it, it does nothing.
    public func screenTitle(_ title: String) -> some View {
        modifier(ScreenTitleModifier(title: title))
    }

    /// The one `.userActivity` of the scene: publishes the frontmost `screenTitle(_:)` as the current activity's
    /// title. Every titled screen registers here instead of publishing an activity of its own, so which one is
    /// current never depends on how SwiftUI picks between several activities of one type.
    public func publishesScreenTitle() -> some View {
        modifier(ScreenTitlePublisher())
    }
}

private struct ScreenTitleModifier: ViewModifier {
    let title: String
    @Environment(ScreenTitleRegistry.self) private var registry: ScreenTitleRegistry?
    @Environment(\.screenTitleDepth) private var depth
    @State private var id = UUID()
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .environment(\.screenTitle, title)
            .environment(\.screenTitleDepth, depth + 1)
            .onAppear {
                isShown = true
                registry?.show(id, depth: depth + 1, title: title)
            }
            // Only while shown: a screen covered by a pushed page is still there, and must not come back in front.
            .onChange(of: title) { if isShown { registry?.show(id, depth: depth + 1, title: title) } }
            .onDisappear {
                isShown = false
                registry?.hide(id)
            }
    }
}

private struct ScreenTitlePublisher: ViewModifier {
    @State private var registry = ScreenTitleRegistry()

    func body(content: Content) -> some View {
        // Read here, in the body, so the activity is updated whenever the frontmost title changes.
        let title = registry.stack.front
        content
            .environment(registry)
            .userActivity(ExodusActivity.viewing, isActive: title != nil) { activity in
                activity.title = title
                activity.isEligibleForHandoff = false
                activity.isEligibleForSearch = false
                activity.isEligibleForPrediction = false
            }
    }
}
