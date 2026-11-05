import Foundation
import LockedShared

/// Extension → Bridge messages (see SPEC "Native messaging protocol").
public enum IncomingMessage: Equatable {
    case hello(version: String?)
    case ping
    /// Valid JSON object with an unrecognized or missing `type`.
    case unknown(type: String?)

    /// Longest `hello.version` kept (Chrome manifest versions are at most 4 dot-separated integers).
    public static let maxVersionLength = 64

    /// Returns nil if the payload isn't a JSON object.
    public static func parse(_ payload: Data) -> IncomingMessage? {
        guard let obj = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return nil }
        let type = obj["type"] as? String
        switch type {
        case "hello":
            // The version ends up in bridge-heartbeat.json (rewritten every 2s): keep it short.
            return .hello(version: (obj["version"] as? String).map { String($0.prefix(maxVersionLength)) })
        case "ping": return .ping
        default: return .unknown(type: type)
        }
    }
}

/// Bridge → Extension `state` message.
///
/// Active:   `{"type":"state","active":true,"endsAt":"<ISO>","websites":[{"url":..,"scope":..}],"youtubeVideoIds":[..]}`
/// Inactive: `{"type":"state","active":false}`
public struct StateMessage: Codable, Equatable {
    public struct Website: Codable, Equatable {
        public var url: String
        public var scope: WebsiteScope

        public init(url: String, scope: WebsiteScope) {
            self.url = url
            self.scope = scope
        }
    }

    public var type: String
    public var active: Bool
    public var endsAt: Date?
    public var websites: [Website]?
    public var youtubeVideoIds: [String]?

    public static let inactive = StateMessage(type: "state", active: false, endsAt: nil, websites: nil, youtubeVideoIds: nil)

    /// Builds the message for the given session. A missing or expired session (`endsAt <= now`) is inactive.
    public init(session: SessionState?, now: Date = Date()) {
        guard let session, session.isActive(at: now) else {
            self = .inactive
            return
        }
        var seen = Set<String>()
        let ids = session.allowlist.youtube.map(\.videoId).filter { seen.insert($0).inserted }
        self.init(
            type: "state",
            active: true,
            endsAt: session.endsAt,
            websites: session.allowlist.websites.map { Website(url: $0.url, scope: $0.scope) },
            youtubeVideoIds: ids
        )
    }

    public init(type: String, active: Bool, endsAt: Date?, websites: [Website]?, youtubeVideoIds: [String]?) {
        self.type = type
        self.active = active
        self.endsAt = endsAt
        self.websites = websites
        self.youtubeVideoIds = youtubeVideoIds
    }

    /// Compact JSON (sorted keys, ISO-8601 dates). Nil fields are omitted.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
