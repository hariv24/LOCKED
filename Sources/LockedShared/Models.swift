import Foundation

public enum WebsiteScope: String, Codable, CaseIterable, Sendable {
    case page
    case domain
}

public struct WebsiteEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var url: String
    public var scope: WebsiteScope

    public init(id: UUID = UUID(), url: String, scope: WebsiteScope) {
        self.id = id
        self.url = url
        self.scope = scope
    }
}

public struct AllowedApp: Codable, Hashable, Identifiable, Sendable {
    public var bundleId: String
    public var name: String
    public var path: String?
    public var id: String { bundleId }

    public init(bundleId: String, name: String, path: String? = nil) {
        self.bundleId = bundleId
        self.name = name
        self.path = path
    }
}

public struct PDFEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var path: String

    public init(id: UUID = UUID(), path: String) {
        self.id = id
        self.path = path
    }

    public var fileName: String { (path as NSString).lastPathComponent }
}

public struct YouTubeEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var videoId: String
    public var title: String?

    public init(id: UUID = UUID(), videoId: String, title: String? = nil) {
        self.id = id
        self.videoId = videoId
        self.title = title
    }

    public var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(videoId)")! }
}

public struct Allowlist: Codable, Hashable, Sendable {
    public var apps: [AllowedApp]
    public var websites: [WebsiteEntry]
    public var youtube: [YouTubeEntry]
    public var pdfs: [PDFEntry]

    public init(apps: [AllowedApp] = [], websites: [WebsiteEntry] = [], youtube: [YouTubeEntry] = [], pdfs: [PDFEntry] = []) {
        self.apps = apps
        self.websites = websites
        self.youtube = youtube
        self.pdfs = pdfs
    }

    /// True if Chrome is needed during the session (any web content is allowlisted).
    public var needsBrowser: Bool { !websites.isEmpty || !youtube.isEmpty }

    public var isEmpty: Bool { apps.isEmpty && websites.isEmpty && youtube.isEmpty && pdfs.isEmpty }
}

public struct Preset: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var allowlist: Allowlist
    public var durationMinutes: Int

    public init(id: UUID = UUID(), name: String, allowlist: Allowlist, durationMinutes: Int) {
        self.id = id
        self.name = name
        self.allowlist = allowlist
        self.durationMinutes = durationMinutes
    }
}

public struct SessionState: Codable, Hashable, Sendable {
    public var version: Int
    public var sessionId: UUID
    public var startedAt: Date
    public var endsAt: Date
    public var allowlist: Allowlist

    public init(version: Int = 1, sessionId: UUID = UUID(), startedAt: Date, endsAt: Date, allowlist: Allowlist) {
        self.version = version
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.allowlist = allowlist
    }

    public func isActive(at now: Date = Date()) -> Bool { endsAt > now }
    public func remaining(at now: Date = Date()) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }
}

public enum SessionOutcome: String, Codable, Sendable {
    case completed
    case exitedEarly
}

public struct HistoryEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var plannedEndAt: Date
    public var endedAt: Date
    public var outcome: SessionOutcome

    public init(id: UUID = UUID(), startedAt: Date, plannedEndAt: Date, endedAt: Date, outcome: SessionOutcome) {
        self.id = id
        self.startedAt = startedAt
        self.plannedEndAt = plannedEndAt
        self.endedAt = endedAt
        self.outcome = outcome
    }
}

public struct BridgeHeartbeat: Codable, Hashable, Sendable {
    public var lastSeen: Date
    public var extensionVersion: String?

    public init(lastSeen: Date, extensionVersion: String? = nil) {
        self.lastSeen = lastSeen
        self.extensionVersion = extensionVersion
    }

    public func isFresh(at now: Date = Date(), maxAge: TimeInterval = LockedConstants.heartbeatMaxAge) -> Bool {
        now.timeIntervalSince(lastSeen) < maxAge
    }
}
