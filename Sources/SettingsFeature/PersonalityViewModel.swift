import Foundation
import Models
import Observation

/// Settings → Personality: the desktop's `PersonalitySchema`, edited as a form and saved as the whole column.
@MainActor
@Observable
public final class PersonalityViewModel {
    /// The schema's `baseStyle` enum, in the desktop's order.
    public static let baseStyles = ["default", "professional", "friendly", "candid", "quirky", "efficient", "cynical"]
    /// The schema's enum for `warm`, `enthusiastic`, `headersAndLists` and `emoji`.
    public static let levels = ["default", "more", "less"]

    public var nickname = ""
    public var occupation = ""
    public var aboutYou = ""
    public var customInstructions = ""
    public var baseStyle = "default"
    public var warm = "default"
    public var enthusiastic = "default"
    public var headersAndLists = "default"
    public var emoji = "default"

    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var hasLoaded = false
    public var errorMessage: String?

    /// The form as it was filled from the column last loaded or saved: only fields that differ from it are
    /// written, so a field the desktop changed since and the user did not touch keeps the desktop's value.
    private var baseline = FormValues()
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public var hasChanges: Bool { hasLoaded && current != baseline }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let snapshot = try await store.load(requiring: [SettingsColumn.personality.name])
            apply(snapshot.personality ?? SettingsColumn.personality.emptyValue)
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Pull to refresh: the column as the server holds it now, with the fields edited here kept on top.
    public func refresh() async {
        guard hasChanges else { return await load() }
        errorMessage = nil
        do {
            let snapshot = try await store.load(requiring: [SettingsColumn.personality.name])
            let fresh = snapshot.personality ?? SettingsColumn.personality.emptyValue
            let merged = edited(fresh)
            apply(fresh)
            fill(merged)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes the fields the user changed into the column as the server holds it now; every other field, and every
    /// key this app does not model, stays as it is there.
    @discardableResult
    public func save() async -> Bool {
        guard hasLoaded else {
            errorMessage = String(
                localized: "ios:settings.error.notLoaded",
                defaultValue: "Connect to the server and load its settings before saving.",
                comment: "Error shown when saving is attempted before the server's settings were loaded.")
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let written = try await store.update(.personality) { $0 = edited($0) }
            apply(written)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// `base` with the fields the user changed written into it. An emptied text field is sent as absent.
    func edited(_ base: PersonalitySettings) -> PersonalitySettings {
        var value = base
        let now = current
        if now.nickname != baseline.nickname { value.nickname = Self.optional(now.nickname) }
        if now.occupation != baseline.occupation { value.occupation = Self.optional(now.occupation) }
        if now.aboutYou != baseline.aboutYou { value.aboutYou = Self.optional(now.aboutYou) }
        if now.customInstructions != baseline.customInstructions {
            value.customInstructions = Self.optional(now.customInstructions)
        }
        if now.baseStyle != baseline.baseStyle { value.baseStyle = now.baseStyle }
        if now.warm != baseline.warm { value.warm = now.warm }
        if now.enthusiastic != baseline.enthusiastic { value.enthusiastic = now.enthusiastic }
        if now.headersAndLists != baseline.headersAndLists { value.headersAndLists = now.headersAndLists }
        if now.emoji != baseline.emoji { value.emoji = now.emoji }
        return value
    }

    private var current: FormValues {
        FormValues(
            nickname: nickname, occupation: occupation, aboutYou: aboutYou, customInstructions: customInstructions,
            baseStyle: baseStyle, warm: warm, enthusiastic: enthusiastic, headersAndLists: headersAndLists,
            emoji: emoji)
    }

    /// Shows `value` and makes it the baseline.
    private func apply(_ value: PersonalitySettings) {
        fill(value)
        baseline = current
    }

    private func fill(_ value: PersonalitySettings) {
        nickname = value.nickname ?? ""
        occupation = value.occupation ?? ""
        aboutYou = value.aboutYou ?? ""
        customInstructions = value.customInstructions ?? ""
        baseStyle = value.baseStyle
        warm = value.warm
        enthusiastic = value.enthusiastic
        headersAndLists = value.headersAndLists
        emoji = value.emoji
    }

    private static func optional(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private struct FormValues: Equatable {
        var nickname = ""
        var occupation = ""
        var aboutYou = ""
        var customInstructions = ""
        var baseStyle = "default"
        var warm = "default"
        var enthusiastic = "default"
        var headersAndLists = "default"
        var emoji = "default"
    }
}
