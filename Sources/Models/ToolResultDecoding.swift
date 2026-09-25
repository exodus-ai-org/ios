import Foundation

/// A shape read leniently out of a `JSONValue`: unknown keys are ignored, a field of the wrong type reads as absent,
/// and `init?(json:)` fails only when what makes the shape recognisable is missing.
public protocol JSONValueDecodable: Decodable, Equatable, Sendable {
    init?(json: JSONValue)
}

extension JSONValueDecodable {
    public init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard let decoded = Self(json: value) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not a \(Self.self)"))
        }
        self = decoded
    }
}

extension JSONValue {
    /// The object, also when it arrived as JSON text (a tool that wraps its result in a text block).
    public var objectValue: [String: JSONValue]? {
        switch self {
        case .object(let object):
            return object
        case .string(let text):
            guard text.first == "{", let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
                case .object(let object) = parsed
            else { return nil }
            return object
        default:
            return nil
        }
    }
}

/// Typed, forgiving reads of one JSON object's fields.
struct JSONFields {
    let raw: [String: JSONValue]

    init?(_ value: JSONValue?) {
        guard let object = value?.objectValue else { return nil }
        raw = object
    }

    func string(_ key: String) -> String? { raw[key]?.stringValue }

    func nonEmpty(_ key: String) -> String? { string(key).flatMap { $0.isEmpty ? nil : $0 } }

    /// Text, or a number written out (the weather tool sends numbers as strings; an older row may not).
    func text(_ key: String) -> String? {
        switch raw[key] {
        case .string(let text)?: text
        case .number(let number)? where number.isFinite:
            Int(exactly: number).map(String.init) ?? String(number)
        default: nil
        }
    }

    func double(_ key: String) -> Double? {
        switch raw[key] {
        case .number(let number)? where number.isFinite: number
        case .string(let text)?: Double(text).flatMap { $0.isFinite ? $0 : nil }
        default: nil
        }
    }

    func int(_ key: String) -> Int? {
        switch raw[key] {
        case .number(let number)?: Int(exactly: number)
        case .string(let text)?: Int(text)
        default: nil
        }
    }

    func bool(_ key: String) -> Bool? { raw[key]?.boolValue }

    func strings(_ key: String) -> [String] {
        guard case .array(let items)? = raw[key] else { return [] }
        return items.compactMap(\.stringValue)
    }

    func array(_ key: String) -> [JSONValue]? {
        if case .array(let items)? = raw[key] { items } else { nil }
    }

    func decoded<T: JSONValueDecodable>(_ key: String) -> T? { raw[key].flatMap(T.init(json:)) }

    /// The items that decode; one bad item does not cost the others.
    func list<T: JSONValueDecodable>(_ key: String) -> [T] { (array(key) ?? []).compactMap(T.init(json:)) }
}
