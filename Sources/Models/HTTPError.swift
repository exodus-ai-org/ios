import Foundation

public struct HTTPError: Error, Equatable, Sendable, LocalizedError {
    public var statusCode: Int
    public var code: String
    public var message: String
    /// The envelope's `params` (the desktop's `AppError.params`), numbers written as text.
    public var params: [String: String]

    public init(statusCode: Int, code: String, message: String, params: [String: String] = [:]) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
        self.params = params
    }

    public var errorDescription: String? { message }

    /// A saved secret the request relied on cannot be used there (its address changed, or a mask was edited).
    public static let secretReentryRequired = "SECRET_REENTRY_REQUIRED"

    /// The field a `SECRET_REENTRY_REQUIRED` answer names (`params.field`), or nil for any other error.
    public var reentryField: String? {
        guard code == Self.secretReentryRequired else { return nil }
        return params["field"]
    }
}

public struct ServerErrorEnvelope: Decodable, Sendable {
    public struct ErrorBody: Decodable, Sendable {
        public var code: String
        public var message: String
        public var params: [String: String]

        private enum CodingKeys: String, CodingKey { case code, message, params }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decode(String.self, forKey: .code)
            message = try container.decode(String.self, forKey: .message)
            let raw = (try? container.decodeIfPresent([String: JSONValue].self, forKey: .params)) ?? [:]
            params = raw.compactMapValues { value in
                switch value {
                case .string(let text): text
                case .number(let number) where number.rounded() == number && abs(number) < 1e15: String(Int64(number))
                case .number(let number): String(number)
                default: nil
                }
            }
        }
    }

    public var type: String
    public var error: ErrorBody
}
