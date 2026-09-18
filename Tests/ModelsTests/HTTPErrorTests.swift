import Foundation
import Testing

@testable import Models

@Suite("HTTPError")
struct HTTPErrorTests {
    @Test("decodes the Anthropic-style error envelope")
    func decodesErrorEnvelope() throws {
        let json = """
            {"type":"error","error":{"code":"VALIDATION_FAILED","message":"API key is required"}}
            """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(ServerErrorEnvelope.self, from: json)
        #expect(envelope.error.code == "VALIDATION_FAILED")
        #expect(envelope.error.message == "API key is required")
    }

    @Test("errorDescription surfaces the message for SwiftUI error alerts")
    func errorDescription() {
        let error = HTTPError(statusCode: 400, code: "VALIDATION_FAILED", message: "API key is required")
        #expect(error.errorDescription == "API key is required")
    }
}
