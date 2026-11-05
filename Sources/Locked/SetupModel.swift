import AppKit
import Foundation
import LockedShared

/// Draft allowlist + duration edited on the setup screen, plus presets.
@MainActor
final class SetupModel: ObservableObject {
    static let shared = SetupModel()

    @Published var allowlist = Allowlist()
    @Published var durationMinutes = 50
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var isScanning = false
    @Published private(set) var presets: [Preset] = []
    @Published var presetError: String?

    private var didStartScan = false
    private var didApplySuggestions = false

    /// Apps that can't be picked: Locked is always allowed, Chrome follows the website rule.
    static let unpickableBundleIds: Set<String> = [LockedConstants.appBundleId, LockedConstants.chromeBundleId]

    private init() {
        presets = LockedStore.loadPresets()
    }

    // MARK: Apps

    var selectableApps: [InstalledApp] {
        installedApps.filter { !Self.unpickableBundleIds.contains($0.bundleId) }
    }

    func scanAppsIfNeeded() {
        guard !didStartScan else { return }
        didStartScan = true
        isScanning = true
        Task {
            let apps = await Task.detached(priority: .userInitiated) {
                InstalledAppScanner.scan()
            }.value
            self.installedApps = apps
            self.isScanning = false
            self.applySuggestionsIfNeeded()
        }
    }

    /// Pre-checks `LockedConstants.suggestedAppBundleIds` that are installed (once, only if no apps are chosen yet).
    private func applySuggestionsIfNeeded() {
        guard !didApplySuggestions else { return }
        didApplySuggestions = true
        guard allowlist.apps.isEmpty else { return }
        for bundleId in LockedConstants.suggestedAppBundleIds {
            if let app = installedApps.first(where: { $0.bundleId == bundleId }) {
                setApp(app, selected: true)
            }
        }
    }

    func isAppSelected(_ bundleId: String) -> Bool {
        allowlist.apps.contains { $0.bundleId == bundleId }
    }

    func setApp(_ app: InstalledApp, selected: Bool) {
        if selected {
            guard !isAppSelected(app.bundleId) else { return }
            allowlist.apps.append(AllowedApp(bundleId: app.bundleId, name: app.name, path: app.path))
        } else {
            allowlist.apps.removeAll { $0.bundleId == app.bundleId }
        }
    }

    func removeApp(bundleId: String) {
        allowlist.apps.removeAll { $0.bundleId == bundleId }
    }

    /// Returns an error message, or nil on success.
    func addOtherApp(at url: URL) -> String? {
        guard let app = InstalledAppScanner.makeApp(at: url) else {
            return "That app has no bundle identifier, so it can't be allowlisted."
        }
        if app.bundleId == LockedConstants.chromeBundleId {
            return "Chrome is allowed automatically when you add websites or YouTube videos."
        }
        if app.bundleId == LockedConstants.appBundleId {
            return "Locked is always allowed."
        }
        setApp(app, selected: true)
        return nil
    }

    // MARK: Websites

    /// Adds https:// if missing. Domain scope keeps only scheme + host (+ :port if given). Returns nil if invalid.
    static func normalizeWebsite(_ input: String, scope: WebsiteScope) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            if text.contains("://") { return nil }
            text = "https://" + text
        }
        guard let components = URLComponents(string: text),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              host.contains(".") || host == "localhost" else { return nil }
        switch scope {
        case .domain:
            let scheme = components.scheme?.lowercased() ?? "https"
            let port = components.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)"
        case .page:
            return text
        }
    }

    /// Returns an error message, or nil on success.
    func addWebsite(_ input: String, scope: WebsiteScope) -> String? {
        guard let url = Self.normalizeWebsite(input, scope: scope) else {
            return "That doesn't look like a website address."
        }
        if !allowlist.websites.contains(where: { $0.url == url && $0.scope == scope }) {
            allowlist.websites.append(WebsiteEntry(url: url, scope: scope))
        }
        return nil
    }

    func addAISites() {
        for preset in LockedConstants.aiSitePresets {
            _ = addWebsite(preset.url, scope: .domain)
        }
    }

    func removeWebsite(id: UUID) {
        allowlist.websites.removeAll { $0.id == id }
    }

    // MARK: YouTube

    /// Returns an error message, or nil on success.
    func addYouTube(_ input: String) -> String? {
        guard let videoId = YouTubeURL.videoId(from: input) else {
            return "That isn't a valid YouTube video link."
        }
        if !allowlist.youtube.contains(where: { $0.videoId == videoId }) {
            allowlist.youtube.append(YouTubeEntry(videoId: videoId))
        }
        return nil
    }

    func removeYouTube(id: UUID) {
        allowlist.youtube.removeAll { $0.id == id }
    }

    // MARK: PDFs

    func addPDFs(_ urls: [URL]) {
        for url in urls {
            let path = url.standardizedFileURL.path
            if !allowlist.pdfs.contains(where: { $0.path == path }) {
                allowlist.pdfs.append(PDFEntry(path: path))
            }
        }
    }

    func removePDF(id: UUID) {
        allowlist.pdfs.removeAll { $0.id == id }
    }

    // MARK: Duration

    func setDuration(_ minutes: Int) {
        durationMinutes = min(max(minutes, SessionManager.minDurationMinutes), SessionManager.maxDurationMinutes)
    }

    // MARK: Presets

    func savePreset(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let index = presets.firstIndex(where: { $0.name == name }) {
            presets[index].allowlist = allowlist
            presets[index].durationMinutes = durationMinutes
        } else {
            presets.append(Preset(name: name, allowlist: allowlist, durationMinutes: durationMinutes))
        }
        persistPresets()
    }

    func loadPreset(_ preset: Preset) {
        allowlist = preset.allowlist
        setDuration(preset.durationMinutes)
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    private func persistPresets() {
        do {
            try LockedStore.savePresets(presets)
            presetError = nil
        } catch {
            presetError = "Couldn't save presets: \(error.localizedDescription)"
        }
    }
}
