import AppKit
import Foundation
import UniformTypeIdentifiers
import LockedShared

struct InstalledApp: Identifiable, Hashable, Sendable {
    let bundleId: String
    let name: String
    let path: String

    var id: String { bundleId }
}

/// Finds .app bundles in /Applications, /System/Applications and ~/Applications (2 folder levels deep).
enum InstalledAppScanner {
    static var searchRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    /// Safe to call off the main thread (Foundation only).
    static func scan() -> [InstalledApp] {
        let fm = FileManager.default
        var byBundleId: [String: InstalledApp] = [:]
        for root in searchRoots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    if let app = makeApp(at: url), byBundleId[app.bundleId] == nil {
                        byBundleId[app.bundleId] = app
                    }
                } else if enumerator.level >= 2 {
                    enumerator.skipDescendants()
                }
            }
        }
        return byBundleId.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func makeApp(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier else { return nil }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.lowercased().hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        return InstalledApp(bundleId: bundleId, name: name, path: url.path)
    }
}

/// Caches app icons by path so list rows don't hit NSWorkspace on every render.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    private init() {}

    func icon(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }

    func icon(for app: AllowedApp) -> NSImage {
        if let path = app.path, FileManager.default.fileExists(atPath: path) {
            return icon(forPath: path)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            return icon(forPath: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}
