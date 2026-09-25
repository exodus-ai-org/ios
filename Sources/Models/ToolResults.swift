import Foundation

// The `details` (and call arguments) the desktop's built-in tools produce, with its field names
// (src/main/lib/ai/calling-tools/*.ts, packages/shared/src/types/*.ts).

// MARK: - terminal

/// `{command, cwd, exitCode, stdout, stderr}`; `exitCode` may be a signal name.
public struct TerminalResult: JSONValueDecodable {
    public let command: String
    public let cwd: String?
    public let exitCode: String?
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == "0" }

    public init(command: String, cwd: String?, exitCode: String?, stdout: String, stderr: String) {
        self.command = command
        self.cwd = cwd
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let command = fields.string("command") else { return nil }
        let exitCode: String? =
            switch fields.raw["exitCode"] {
            case .number(let number)?: Int(exactly: number).map(String.init)
            case .string(let text)? where !text.isEmpty: text
            default: nil
            }
        self.init(
            command: command, cwd: fields.nonEmpty("cwd"), exitCode: exitCode, stdout: fields.string("stdout") ?? "",
            stderr: fields.string("stderr") ?? "")
    }
}

// MARK: - read_file / write_file / edit_file

/// read_file's arguments `{path, encoding?}`.
public struct ReadFileArguments: JSONValueDecodable {
    public let path: String
    public let encoding: String?

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let path = fields.string("path") else { return nil }
        self.path = path
        encoding = fields.nonEmpty("encoding")
    }
}

/// read_file's details `{path, content, size}`.
public struct ReadFileResult: JSONValueDecodable {
    public let path: String
    public let content: String
    public let size: Int?

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let content = fields.string("content") else { return nil }
        path = fields.string("path") ?? ""
        self.content = content
        size = fields.int("size")
    }
}

/// write_file's arguments `{path, content, append?}`.
public struct WriteFileArguments: JSONValueDecodable {
    public let path: String
    public let content: String
    public let append: Bool

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let path = fields.string("path") else { return nil }
        self.path = path
        content = fields.string("content") ?? ""
        append = fields.bool("append") ?? false
    }
}

/// write_file's details `{path, bytes, appended}`.
public struct WriteFileResult: JSONValueDecodable {
    public let path: String
    public let bytes: Int?
    public let appended: Bool

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let path = fields.string("path") else { return nil }
        self.path = path
        bytes = fields.int("bytes")
        appended = fields.bool("appended") ?? false
    }
}

/// edit_file's arguments `{path, old_string, new_string, replace_all?}`: the diff is built from these.
public struct EditFileArguments: JSONValueDecodable {
    public let path: String
    public let oldString: String
    public let newString: String
    public let replaceAll: Bool

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let path = fields.string("path") else { return nil }
        self.path = path
        oldString = fields.string("old_string") ?? ""
        newString = fields.string("new_string") ?? ""
        replaceAll = fields.bool("replace_all") ?? false
    }
}

/// edit_file's details `{path, replacements, linesBefore, linesAfter}`: counts only.
public struct EditFileResult: JSONValueDecodable {
    public let path: String
    public let replacements: Int?
    public let linesBefore: Int?
    public let linesAfter: Int?

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let path = fields.string("path") else { return nil }
        self.path = path
        replacements = fields.int("replacements")
        linesBefore = fields.int("linesBefore")
        linesAfter = fields.int("linesAfter")
    }
}

// MARK: - computer_use

/// computer_use's arguments `{task, target}`.
public struct ComputerUseArguments: JSONValueDecodable {
    public let task: String
    public let target: String

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let task = fields.string("task") else { return nil }
        self.task = task
        target = fields.string("target") ?? ""
    }
}

/// A live frame while the session runs: `{sessionId, step, action?, thumbnail?, awaitingHuman?: {question}}`.
public struct ComputerUseFrame: Equatable, Sendable {
    public let sessionId: String?
    public let step: Int
    public let action: String?
    /// Base64 PNG, as the desktop sends it.
    public let thumbnail: String?
    public let awaitingHumanQuestion: String?
}

/// The end of a session: `{sessionId, outcome, steps, summary}`.
public struct ComputerUseOutcome: Equatable, Sendable {
    public let sessionId: String?
    /// `success`, `failed`, `aborted`, `stuck`, …: kept raw so a new outcome still shows.
    public let outcome: String
    public let steps: Int?
    public let summary: String
}

public enum ComputerUseDetails: JSONValueDecodable {
    case frame(ComputerUseFrame)
    case finished(ComputerUseOutcome)
    /// `{error}`: `disabled`, `not-allowed` or a message.
    case failed(String)

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json) else { return nil }
        if let error = fields.string("error") {
            self = .failed(error)
        } else if let outcome = fields.string("outcome"), fields.int("step") == nil {
            self = .finished(
                ComputerUseOutcome(
                    sessionId: fields.string("sessionId"), outcome: outcome, steps: fields.int("steps"),
                    summary: fields.string("summary") ?? ""))
        } else if let step = fields.int("step") {
            let question: String? =
                if case .object(let asking)? = fields.raw["awaitingHuman"] { asking["question"]?.stringValue } else { nil }
            self = .frame(
                ComputerUseFrame(
                    sessionId: fields.string("sessionId"), step: step, action: fields.nonEmpty("action"),
                    thumbnail: fields.nonEmpty("thumbnail"), awaitingHumanQuestion: question))
        } else {
            return nil
        }
    }
}

// MARK: - deep_research

/// deep_research's arguments `{subject}`.
public struct DeepResearchArguments: JSONValueDecodable {
    public let subject: String

    public init?(json: JSONValue) {
        guard let subject = JSONFields(json)?.string("subject") else { return nil }
        self.subject = subject
    }
}

/// `{id, toolCallId}` (the job to read from `GET /api/v1/deep-research/result/:id`), or `{error}`.
public enum DeepResearchResult: JSONValueDecodable {
    case started(id: String)
    case failed(String)

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json) else { return nil }
        if let id = fields.nonEmpty("id") {
            self = .started(id: id)
        } else if let error = fields.string("error") {
            self = .failed(error)
        } else {
            return nil
        }
    }
}

// MARK: - image_generation

/// image_generation's arguments `{prompt}`.
public struct ImageGenerationArguments: JSONValueDecodable {
    public let prompt: String

    public init?(json: JSONValue) {
        guard let prompt = JSONFields(json)?.string("prompt") else { return nil }
        self.prompt = prompt
    }
}

/// One generated image. New rows name a file the desktop serves (`mediaId`, `chatId`, `mimeType`); older ones carry a
/// `data:` or https `url` (or `dataUrl`), and some carry none.
public struct GeneratedImage: JSONValueDecodable {
    public enum Source: Equatable, Sendable {
        case media(id: String, chatId: String?, mimeType: String?)
        case dataURL(String)
        case remote(URL)
    }

    public let mediaId: String?
    public let chatId: String?
    public let mimeType: String?
    public let url: String?
    public let dataUrl: String?
    public let revisedPrompt: String?
    /// The file's own size in pixels, when the desktop could read it from the header.
    public let width: Int?
    public let height: Int?

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json) else { return nil }
        mediaId = fields.nonEmpty("mediaId")
        chatId = fields.nonEmpty("chatId")
        mimeType = fields.nonEmpty("mimeType")
        url = fields.nonEmpty("url")
        dataUrl = fields.nonEmpty("dataUrl")
        revisedPrompt = fields.nonEmpty("revisedPrompt")
        width = fields.int("width").flatMap { $0 > 0 ? $0 : nil }
        height = fields.int("height").flatMap { $0 > 0 ? $0 : nil }
    }

    /// Where the pixels are, in order of preference; nil when the row carries none.
    public var source: Source? {
        if let mediaId { return .media(id: mediaId, chatId: chatId, mimeType: mimeType) }
        if let dataUrl, Self.isInlineImage(dataUrl) { return .dataURL(dataUrl) }
        if let url, Self.isInlineImage(url) { return .dataURL(url) }
        if let url, let parsed = URL(string: url), parsed.scheme == "https" || parsed.scheme == "http" {
            return .remote(parsed)
        }
        return nil
    }

    // Raster types only, like the desktop's markdown allowlist: a `data:text/html` or an SVG (which can name remote
    // resources) never reaches a decoder.
    private static func isInlineImage(_ text: String) -> Bool {
        text.prefix(24).lowercased().firstMatch(of: /^data:image\/(png|jpe?g|gif|webp|avif)[;,]/) != nil
    }
}

/// image_generation's details `{images, size?}`.
public struct ImageGenerationResult: JSONValueDecodable {
    public let images: [GeneratedImage]
    /// The size the request asked for, such as `1024x1536` or `auto`.
    public let size: String?

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), fields.array("images") != nil else { return nil }
        images = fields.list("images")
        size = fields.nonEmpty("size")
    }
}

// MARK: - map_itinerary

/// A non-fatal condition a tool reports alongside its result (`ToolNotice`).
public struct ToolNotice: JSONValueDecodable {
    /// `warning` or `info`.
    public let level: String
    public let message: String

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let message = fields.string("message") else { return nil }
        level = fields.string("level") ?? "info"
        self.message = message
    }
}

/// map_itinerary's details: `{type: "mapItinerary", title?, days: [{label, title?, summary?, routeMode?, places}],
/// notice?}`. Places carry the model's name and coordinates plus whatever Places enrichment added.
public struct MapItineraryDetails: JSONValueDecodable {
    public struct Review: JSONValueDecodable {
        public let author: String?
        public let authorPhotoUrl: String?
        public let rating: Double?
        public let text: String?
        public let relativeTime: String?

        public init?(json: JSONValue) {
            guard let fields = JSONFields(json) else { return nil }
            author = fields.nonEmpty("author")
            authorPhotoUrl = fields.nonEmpty("authorPhotoUrl")
            rating = fields.double("rating")
            text = fields.nonEmpty("text")
            relativeTime = fields.nonEmpty("relativeTime")
        }
    }

    public struct Place: JSONValueDecodable {
        public let name: String
        /// Both set, or both nil: a place without a readable position (missing, not a number, out of range) is still
        /// a stop of its day, only not on the map.
        public let lat: Double?
        public let lng: Double?
        public let type: String?
        public let timeLabel: String?
        public let note: String?
        public let rating: Double?
        public let reviewCount: Int?
        public let phone: String?
        public let websiteUri: String?
        public let googleMapsUri: String?
        public let address: String?
        public let openNow: Bool?
        public let openingHours: [String]
        /// Places photo paths; a full URL needs the user's Google key, which stays on the computer.
        public let photoNames: [String]
        public let reviews: [Review]

        public init?(json: JSONValue) {
            guard let fields = JSONFields(json), let name = fields.string("name") else { return nil }
            self.name = name
            if let lat = fields.double("lat"), let lng = fields.double("lng"), (-90...90).contains(lat),
                (-180...180).contains(lng)
            {
                self.lat = lat
                self.lng = lng
            } else {
                lat = nil
                lng = nil
            }
            type = fields.nonEmpty("type")
            timeLabel = fields.nonEmpty("timeLabel")
            note = fields.nonEmpty("note")
            rating = fields.double("rating")
            reviewCount = fields.int("reviewCount")
            phone = fields.nonEmpty("phone")
            websiteUri = fields.nonEmpty("websiteUri")
            googleMapsUri = fields.nonEmpty("googleMapsUri")
            address = fields.nonEmpty("address")
            openNow = fields.bool("openNow")
            openingHours = fields.strings("openingHours")
            photoNames = fields.strings("photoNames")
            reviews = fields.list("reviews")
        }
    }

    public struct Day: JSONValueDecodable {
        public let label: String
        public let title: String?
        public let summary: String?
        /// `walking`, `driving` or `transit`.
        public let routeMode: String?
        public let places: [Place]

        public init?(json: JSONValue) {
            guard let fields = JSONFields(json), fields.array("places") != nil else { return nil }
            label = fields.string("label") ?? ""
            title = fields.nonEmpty("title")
            summary = fields.nonEmpty("summary")
            routeMode = fields.nonEmpty("routeMode")
            places = fields.list("places")
        }
    }

    public let title: String?
    public let days: [Day]
    public let notice: ToolNotice?

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), fields.array("days") != nil else { return nil }
        title = fields.nonEmpty("title")
        days = fields.list("days")
        notice = fields.decoded("notice")
    }
}

// MARK: - web_search media

/// One image or video a web search returned alongside its pages (`WebSearchMediaResult`).
public struct WebSearchMedia: JSONValueDecodable {
    public enum Kind: String, Sendable {
        case image, video
    }

    public let kind: Kind
    public let title: String
    public let url: String
    public let sourceUrl: String
    public let thumbnailUrl: String?
    public let source: String?
    public let width: Int?
    public let height: Int?
    public let duration: String?
    public let age: String?
    public let creator: String?
    public let views: Int?
    public let publisher: String?

    public init?(json: JSONValue) {
        guard let fields = JSONFields(json), let kind = fields.string("kind").flatMap(Kind.init(rawValue:)),
            let url = fields.nonEmpty("url")
        else { return nil }
        self.kind = kind
        self.url = url
        title = fields.string("title") ?? ""
        sourceUrl = fields.string("sourceUrl") ?? ""
        thumbnailUrl = fields.nonEmpty("thumbnailUrl")
        source = fields.nonEmpty("source")
        width = fields.int("width")
        height = fields.int("height")
        duration = fields.nonEmpty("duration")
        age = fields.nonEmpty("age")
        creator = fields.nonEmpty("creator")
        views = fields.int("views")
        publisher = fields.nonEmpty("publisher")
    }
}
