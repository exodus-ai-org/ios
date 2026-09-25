import Foundation
import Models
import Testing

@testable import NetworkingKit
@testable import SettingsFeature

@MainActor
@Suite("Settings error reporting")
struct SettingsReportingTests {
    @Test("disabledTools names this app does not know are reported to the computer's log, by name")
    func unknownToolNamesReported() async throws {
        let server = SettingsPageTestServer(rows: [
            #"{"id":"global","lastBackupAt":null,"tools":{"disabledTools":["terminal","future_tool"]}}"#
        ])
        let (_, config) = server.makeClient()
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [RoutedSettingsURLProtocol.self]
        let reporter = LogReporter(session: .shared, serverConfig: config, isReady: { false })
        let client = APIClient(
            session: URLSession(configuration: session), serverConfig: config, reporter: reporter)
        let vm = ToolsSettingsViewModel(store: SettingsStore(apiClient: client))
        await vm.load()
        #expect(vm.unknownDisabledNames == ["future_tool"])

        var entries: [LogReporter.Entry] = []
        for _ in 0..<200 where entries.isEmpty {
            entries = await reporter.pending
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(entries.map(\.scope) == ["settings.tools"])
        #expect(entries.first?.attributes["names"] == .string("future_tool"))
    }
}
