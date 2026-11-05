import Foundation

public enum LockedConstants {
    public static let appBundleId = "app.locked.Locked"
    public static let nativeHostName = "app.locked.bridge"
    public static let extensionId = "labfclmdkmlcipjlibjnohgahngindoo"
    public static let launchAgentLabel = "app.locked.watchdog"
    public static let chromeBundleId = "com.google.Chrome"
    public static let heartbeatMaxAge: TimeInterval = 6
    public static let heartbeatInterval: TimeInterval = 2

    /// Bundle IDs that are never hidden or counted as violations.
    public static let systemAllowedBundleIds: Set<String> = [
        appBundleId,
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.SecurityAgent",
        "com.apple.UserNotificationCenter",
        "com.apple.universalAccessAuthWarn",
        "com.apple.coreservices.uiagent",
    ]

    /// Finder gets hidden but is not treated as a violation (no "pull back" activation spam).
    public static let finderBundleId = "com.apple.finder"

    /// Domains added by the "AI sites" one-click preset (domain scope).
    public static let aiSitePresets: [(name: String, url: String)] = [
        ("ChatGPT", "https://chatgpt.com"),
        ("Claude", "https://claude.ai"),
        ("Gemini", "https://gemini.google.com"),
    ]

    /// Apps pre-suggested in setup if installed.
    public static let suggestedAppBundleIds: [String] = [
        "com.microsoft.VSCode",
        "com.apple.Notes",
        "com.openai.chat",
        "com.anthropic.claudefordesktop",
    ]
}

public enum LockedPaths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    public static var baseDir: URL {
        home.appendingPathComponent("Library/Application Support/Locked", isDirectory: true)
    }

    public static var sessionFile: URL { baseDir.appendingPathComponent("session.json") }
    public static var presetsFile: URL { baseDir.appendingPathComponent("presets.json") }
    public static var historyFile: URL { baseDir.appendingPathComponent("history.json") }
    public static var heartbeatFile: URL { baseDir.appendingPathComponent("bridge-heartbeat.json") }
    public static var extensionDir: URL { baseDir.appendingPathComponent("ChromeExtension", isDirectory: true) }

    public static var nativeHostManifest: URL {
        home.appendingPathComponent(
            "Library/Application Support/Google/Chrome/NativeMessagingHosts/\(LockedConstants.nativeHostName).json")
    }

    public static var launchAgentPlist: URL {
        home.appendingPathComponent("Library/LaunchAgents/\(LockedConstants.launchAgentLabel).plist")
    }

    public static func ensureBaseDir() throws {
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }
}
