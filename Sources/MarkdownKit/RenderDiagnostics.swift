import SwiftUI

/// Where a view reports that it fell back to a plainer rendering (markup it does not draw, a card it could not
/// read). It says what kind of thing fell back, never the text. The app wires it to its log reporter; MarkdownKit
/// itself depends on nothing that sends anything.
public struct RenderDiagnostics: Sendable {
    public let report: @Sendable (_ scope: String, _ message: String, _ attributes: [String: String]) -> Void

    public init(report: @escaping @Sendable (_ scope: String, _ message: String, _ attributes: [String: String]) -> Void) {
        self.report = report
    }

    public static let none = RenderDiagnostics { _, _, _ in }
}

extension EnvironmentValues {
    @Entry public var renderDiagnostics: RenderDiagnostics = .none
}
