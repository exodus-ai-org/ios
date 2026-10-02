import Foundation
import Testing

@testable import Models

@Suite("Screen titles: what a screenshot is named after")
struct ScreenTitleTests {
    @Test("parts are joined by a middle dot, trimmed, the empty and missing ones dropped")
    func join() {
        #expect(ScreenTitles.join("Settings", "Memory") == "Settings · Memory")
        #expect(ScreenTitles.join("Memories used", "Trip to Kyoto") == "Memories used · Trip to Kyoto")
        #expect(ScreenTitles.join("Settings", "Memory", "New Memory") == "Settings · Memory · New Memory")
        #expect(ScreenTitles.join("  Health ", nil, "", " \n", "Sleep") == "Health · Sleep")
        #expect(ScreenTitles.join("Image", "") == "Image")
        #expect(ScreenTitles.join(nil, nil) == "")
        #expect(ScreenTitles.separator == " \u{00B7} ")
    }

    @Test("nothing titled, nothing in front")
    func empty() {
        #expect(ScreenTitleStack().front == nil)
    }

    @Test("a sheet over a screen is in front, and when it closes the screen beneath is back")
    func sheetOverScreen() {
        var stack = ScreenTitleStack()
        let shell = UUID(), sheet = UUID()
        stack.show(shell, depth: 1, title: "Trip to Kyoto")
        stack.show(sheet, depth: 2, title: "Memories used · Trip to Kyoto")
        #expect(stack.front == "Memories used · Trip to Kyoto")
        stack.hide(sheet)
        #expect(stack.front == "Trip to Kyoto")
    }

    @Test("a nested screen wins even when it appeared before the one it is nested in")
    func deeperWins() {
        var stack = ScreenTitleStack()
        let inner = UUID(), outer = UUID()
        stack.show(inner, depth: 2, title: "Settings · Memory")
        stack.show(outer, depth: 1, title: "Trip to Kyoto")
        #expect(stack.front == "Settings · Memory")
    }

    @Test("at one depth the screen shown last is in front")
    func lastShownWins() {
        var stack = ScreenTitleStack()
        let first = UUID(), second = UUID()
        stack.show(first, depth: 2, title: "1 other version · Chat")
        stack.show(second, depth: 2, title: "Sources · Chat")
        #expect(stack.front == "Sources · Chat")
        stack.hide(second)
        #expect(stack.front == "1 other version · Chat")
    }

    @Test("a title changing keeps its place: the screen beneath renaming does not jump in front")
    func retitleKeepsOrder() {
        var stack = ScreenTitleStack()
        let chat = UUID(), settings = UUID()
        stack.show(chat, depth: 1, title: "New chat")
        stack.show(settings, depth: 1, title: "Settings")
        stack.show(chat, depth: 1, title: "Trip to Kyoto")
        #expect(stack.front == "Settings")
        stack.hide(settings)
        #expect(stack.front == "Trip to Kyoto")
    }
}
