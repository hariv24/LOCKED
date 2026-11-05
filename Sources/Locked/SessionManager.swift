import AppKit
import Foundation
import LockedShared

enum SessionError: LocalizedError {
    case emptyAllowlist
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .emptyAllowlist: return "Add at least one app, website, video or PDF first."
        case .alreadyRunning: return "A session is already running."
        }
    }
}

/// The emergency-exit flow: type the phrase, wait 60s, confirm.
enum EmergencyPhase: Equatable {
    case inactive
    /// `phrase` is displayed in groups of 5 separated by spaces.
    case typing(phrase: String)
    case countdown(endsAt: Date)
    case confirm
}

@MainActor
final class SessionManager: NSObject, ObservableObject {
    static let shared = SessionManager()

    static let emergencyWaitSeconds: TimeInterval = 60
    static let minDurationMinutes = 1
    static let maxDurationMinutes = 600

    @Published private(set) var state: SessionState?
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var emergency: EmergencyPhase = .inactive
    @Published private(set) var emergencyRemaining: TimeInterval = 0

    private var timer: Timer?

    var isActive: Bool { state != nil }

    private override init() {
        super.init()
    }

    // MARK: Start / resume

    func start(allowlist: Allowlist, durationMinutes: Int) throws {
        guard state == nil else { throw SessionError.alreadyRunning }
        guard !allowlist.isEmpty else { throw SessionError.emptyAllowlist }
        let minutes = min(max(durationMinutes, Self.minDurationMinutes), Self.maxDurationMinutes)
        let now = Date()
        let session = SessionState(
            startedAt: now,
            endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)),
            allowlist: allowlist)
        try LockedPaths.ensureBaseDir()
        try LockedStore.saveSession(session)
        LaunchAgentInstaller.install()
        activate(session)
    }

    /// SPEC "On launch": resume an unexpired session, or finish an expired one as completed.
    func resumeOnLaunch() {
        guard state == nil else { return }
        guard let session = LockedStore.loadSession() else {
            // No session but a LaunchAgent plist left over (e.g. from a crash): remove it.
            if !FileManager.default.fileExists(atPath: LockedPaths.sessionFile.path),
               LaunchAgentInstaller.isInstalled {
                LaunchAgentInstaller.uninstall()
            }
            return
        }
        if session.isActive() {
            // Re-installs the LaunchAgent if it's missing; makes sure it's loaded otherwise.
            LaunchAgentInstaller.install()
            activate(session)
        } else {
            state = session
            finish(outcome: .completed)
        }
    }

    private func activate(_ session: SessionState) {
        state = session
        emergency = .inactive
        emergencyRemaining = 0
        remaining = session.remaining()

        AppBlocker.shared.start(allowlist: session.allowlist)
        TimerPillController.shared.show(remaining: remaining)

        timer?.invalidate()
        let t = Timer(timeInterval: 1, target: self, selector: #selector(timerFired(_:)),
                      userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Tick

    @objc private func timerFired(_ timer: Timer) {
        tick()
    }

    private func tick() {
        guard let session = state else { return }
        let now = Date()
        remaining = session.remaining(at: now)
        TimerPillController.shared.update(remaining: remaining)

        if case .countdown(let endsAt) = emergency {
            emergencyRemaining = max(0, endsAt.timeIntervalSince(now))
            if emergencyRemaining <= 0 {
                emergency = .confirm
            }
        }

        if remaining <= 0 {
            finish(outcome: .completed)
            return
        }

        // The bridge and watchdog read session.json; if it vanished mid-session, put it back.
        if !FileManager.default.fileExists(atPath: LockedPaths.sessionFile.path) {
            if (try? LockedStore.saveSession(session)) != nil {
                // The watchdog exits 0 when it sees the file missing, and launchd won't restart a clean exit,
                // so start it again (install() kickstarts the job if it's still loaded).
                LaunchAgentInstaller.install()
            }
        }
    }

    // MARK: Finish

    /// SPEC "Session end": delete session.json, boot out + delete the LaunchAgent,
    /// append a HistoryEntry, post a notification and play a sound.
    func finish(outcome: SessionOutcome) {
        guard let session = state else { return }
        let now = Date()

        timer?.invalidate()
        timer = nil
        AppBlocker.shared.stop()
        TimerPillController.shared.hide()
        PDFViewerController.shared.close()

        LockedStore.clearSession()
        LaunchAgentInstaller.uninstall()

        let endedAt = outcome == .completed ? min(now, session.endsAt) : now
        let entry = HistoryEntry(
            startedAt: session.startedAt,
            plannedEndAt: session.endsAt,
            endedAt: endedAt,
            outcome: outcome)
        do {
            try LockedStore.appendHistory(entry)
        } catch {
            NSLog("Locked: failed to write history: %@", String(describing: error))
        }

        state = nil
        remaining = 0
        emergency = .inactive
        emergencyRemaining = 0

        Notifier.sessionEnded(outcome: outcome)
        MainWindowRouter.shared.showMain()
    }

    // MARK: Emergency exit

    func beginEmergencyExit() {
        guard isActive else { return }
        emergency = .typing(phrase: Self.makePhrase())
        emergencyRemaining = 0
    }

    /// Returns true if the typed text matches the phrase (whitespace ignored, case-sensitive).
    @discardableResult
    func submitEmergencyPhrase(_ typed: String) -> Bool {
        guard case .typing(let phrase) = emergency else { return false }
        guard Self.stripWhitespace(typed) == Self.stripWhitespace(phrase) else { return false }
        emergency = .countdown(endsAt: Date().addingTimeInterval(Self.emergencyWaitSeconds))
        emergencyRemaining = Self.emergencyWaitSeconds
        return true
    }

    func cancelEmergencyExit() {
        emergency = .inactive
        emergencyRemaining = 0
    }

    func confirmEmergencyExit() {
        guard emergency == .confirm else { return }
        finish(outcome: .exitedEarly)
    }

    static func stripWhitespace(_ s: String) -> String {
        s.filter { !$0.isWhitespace }
    }

    /// 40 random letters/digits in 8 groups of 5. Visually ambiguous characters (0 O o 1 l I) are left out.
    static func makePhrase() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789")
        var groups: [String] = []
        for _ in 0..<8 {
            var group = ""
            for _ in 0..<5 {
                group.append(alphabet.randomElement() ?? "x")
            }
            groups.append(group)
        }
        return groups.joined(separator: " ")
    }
}
