import SwiftUI

/// Settings pages another module draws: Settings cannot import the chat, so the App hands them over at launch.
@MainActor
public enum SettingsPageHooks {
    /// Settings › Working cards (`WorkingCardsSettingsPage`), which shows the chat's own cards.
    public static var workingCards: () -> AnyView = { AnyView(EmptyView()) }
}
