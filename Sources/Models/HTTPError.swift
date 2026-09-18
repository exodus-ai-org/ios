import Foundation

public struct HTTPError: Error, Equatable, Sendable, LocalizedError {
    public var statusCode: Int
    public var code: String
    public var message: String

    public init(statusCode: Int, code: String, message: String) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct ServerErrorEnvelope: Decodable, Sendable {
    public struct ErrorBody: Decodable, Sendable {
        public var code: String
        public var message: String
    }

    public var type: String
    public var error: ErrorBody
}
