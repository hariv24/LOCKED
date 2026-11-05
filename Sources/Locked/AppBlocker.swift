import AppKit
import Foundation
import LockedShared

/// Implements SPEC "App-side enforcement rules": hides every regular app that isn't allowed.
@MainActor
final class AppBlocker: NSObject {
    static let shared = AppBlocker()

    private enum Verdict {
        case allowed
        /// Finder is hidden but not treated as a violation.
        case finder
        case blocked
    }

    private var allowlist: Allowlist?
    private var allowedBundleIds: Set<String> = []
    private var timer: Timer?
    private var lastAllowedPid: pid_t?
    private let ownPid = ProcessInfo.processInfo.processIdentifier

    /// When the user opens a website from the session screen while the bridge isn't connected yet,
    /// Chrome gets hidden until its heartbeat arrives. We then bring it back once.
    private var chromeRequestedAt: Date?
    private var chromeWasAllowed = false
    /// When the blocker last hid Chrome because the bridge heartbeat went stale. If the heartbeat comes back
    /// soon after, Chrome is unhidden again (not activated).
    private var chromeHiddenForStaleHeartbeatAt: Date?

    var isRunning: Bool { allowlist != nil }

    private override init() {
        super.init()
    }

    func start(allowlist: Allowlist) {
        stop()
        self.allowlist = allowlist
        allowedBundleIds = Set(allowlist.apps.map { $0.bundleId })
        lastAllowedPid = nil
        chromeRequestedAt = nil
        chromeWasAllowed = false
        chromeHiddenForStaleHeartbeatAt = nil

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appDidActivate(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidLaunch(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)

        let t = Timer(timeInterval: 1, target: self, selector: #selector(timerFired(_:)),
                      userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t

        enforce()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timer?.invalidate()
        timer = nil
        allowlist = nil
        allowedBundleIds = []
        lastAllowedPid = nil
        chromeRequestedAt = nil
        chromeHiddenForStaleHeartbeatAt = nil
    }

    /// Called right before Locked asks Chrome to open an allowed URL.
    func noteChromeRequested() {
        chromeRequestedAt = Date()
    }

    // MARK: Events

    @objc private func appDidActivate(_ note: Notification) {
        guard isRunning else { return }
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.activationPolicy == .regular,
           verdict(for: app, chromeAllowed: isChromeAllowed()) == .allowed {
            lastAllowedPid = app.processIdentifier
        }
        enforce()
    }

    @objc private func appDidLaunch(_ note: Notification) {
        enforce()
    }

    @objc private func timerFired(_ timer: Timer) {
        enforce()
    }

    // MARK: Rules

    private func isChromeAllowed() -> Bool {
        guard let allowlist, allowlist.needsBrowser else { return false }
        return LockedStore.loadHeartbeat()?.isFresh() ?? false
    }

    private func verdict(for app: NSRunningApplication, chromeAllowed: Bool) -> Verdict {
        if app.processIdentifier == ownPid { return .allowed }
        guard let bundleId = app.bundleIdentifier else { return .blocked }
        if LockedConstants.systemAllowedBundleIds.contains(bundleId) { return .allowed }
        if bundleId == LockedConstants.finderBundleId { return .finder }
        // Chrome follows its own rule even if it was added as an app.
        if bundleId == LockedConstants.chromeBundleId { return chromeAllowed ? .allowed : .blocked }
        if allowedBundleIds.contains(bundleId) { return .allowed }
        return .blocked
    }

    func enforce() {
        guard isRunning else { return }
        let chromeAllowed = isChromeAllowed()
        let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var hidFrontmostViolation = false

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, !app.isTerminated else { continue }
            switch verdict(for: app, chromeAllowed: chromeAllowed) {
            case .allowed:
                continue
            case .finder:
                if !app.isHidden {
                    _ = app.hide()
                }
            case .blocked:
                let isFront = app.isActive || app.processIdentifier == frontmostPid
                if !app.isHidden || isFront {
                    if app.bundleIdentifier == LockedConstants.chromeBundleId, allowlist?.needsBrowser == true {
                        // Chrome is blocked only because the heartbeat is stale.
                        chromeHiddenForStaleHeartbeatAt = Date()
                    }
                    _ = app.hide()
                }
                if isFront {
                    hidFrontmostViolation = true
                }
            }
        }

        handleChromeTransition(chromeAllowed: chromeAllowed)

        if hidFrontmostViolation {
            activateFallback(chromeAllowed: chromeAllowed)
        }
    }

    /// If Chrome just became allowed (heartbeat arrived) shortly after the user asked Locked
    /// to open an allowed site, unhide and activate it so the user doesn't have to click again.
    /// If instead the blocker hid Chrome shortly before because the heartbeat went stale, just unhide it.
    private func handleChromeTransition(chromeAllowed: Bool) {
        defer { chromeWasAllowed = chromeAllowed }
        guard chromeAllowed, !chromeWasAllowed else { return }
        let requestedAt = chromeRequestedAt
        let hiddenAt = chromeHiddenForStaleHeartbeatAt
        chromeRequestedAt = nil
        chromeHiddenForStaleHeartbeatAt = nil
        guard let chrome = NSRunningApplication
            .runningApplications(withBundleIdentifier: LockedConstants.chromeBundleId).first else { return }
        let now = Date()
        if let requestedAt, now.timeIntervalSince(requestedAt) < 20 {
            _ = chrome.unhide()
            _ = chrome.activate(options: [])
            lastAllowedPid = chrome.processIdentifier
        } else if let hiddenAt, now.timeIntervalSince(hiddenAt) < 30, chrome.isHidden {
            _ = chrome.unhide()
        }
    }

    /// After hiding a violating frontmost app, activate the most recently used allowed app, or Locked.
    /// (`lastAllowedPid` may be Locked's own pid, in which case Locked's main window comes forward.)
    private func activateFallback(chromeAllowed: Bool) {
        if let pid = lastAllowedPid, pid != ownPid,
           let app = NSRunningApplication(processIdentifier: pid),
           !app.isTerminated,
           verdict(for: app, chromeAllowed: chromeAllowed) == .allowed {
            if app.isHidden {
                _ = app.unhide()
            }
            _ = app.activate(options: [])
            return
        }
        lastAllowedPid = nil
        MainWindowRouter.shared.showMain()
    }
}
