import Foundation
import LockedShared

/// Protocol logic of the native messaging host, independent of stdin/stdout and timers.
///
/// Not thread-safe: the caller must invoke every method from one serial queue.
public final class BridgeController {
    private let loadSession: () -> SessionState?
    private let writeHeartbeat: (BridgeHeartbeat) -> Void
    private let send: (StateMessage) -> Void
    private let now: () -> Date

    /// The last state pushed to the extension. Nil until the extension has said something.
    public private(set) var lastSent: StateMessage?
    public private(set) var extensionVersion: String?

    public init(
        loadSession: @escaping () -> SessionState? = { LockedStore.loadSession() },
        writeHeartbeat: @escaping (BridgeHeartbeat) -> Void,
        send: @escaping (StateMessage) -> Void,
        now: @escaping () -> Date = Date.init
    ) {
        self.loadSession = loadSession
        self.writeHeartbeat = writeHeartbeat
        self.send = send
        self.now = now
    }

    /// The state the extension should currently see, from the session file and the clock.
    public func currentState() -> StateMessage {
        StateMessage(session: loadSession(), now: now())
    }

    public func handle(_ message: IncomingMessage) {
        switch message {
        case .hello(let version):
            extensionVersion = version
            heartbeat()
            pushState(force: true)
        case .ping:
            heartbeat()
            // A ping before any hello (shouldn't happen) still gets the extension in sync.
            if lastSent == nil { pushState(force: true) }
        case .unknown:
            break
        }
    }

    /// Called every second. Pushes state if the session content changed or it expired.
    /// Does nothing until the extension has said hello (or pinged).
    public func poll() {
        guard lastSent != nil else { return }
        pushState(force: false)
    }

    /// Called every 2 seconds while connected.
    public func heartbeat() {
        writeHeartbeat(BridgeHeartbeat(lastSeen: now(), extensionVersion: extensionVersion))
    }

    private func pushState(force: Bool) {
        let state = currentState()
        if !force, state == lastSent { return }
        lastSent = state
        send(state)
    }
}
