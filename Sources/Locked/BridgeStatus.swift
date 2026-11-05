import Foundation
import LockedShared

/// Polls `bridge-heartbeat.json` every 2s and publishes whether Chrome's extension is connected.
@MainActor
final class BridgeStatus: NSObject, ObservableObject {
    static let shared = BridgeStatus()

    @Published private(set) var isConnected = false
    @Published private(set) var extensionVersion: String?

    private var timer: Timer?

    private override init() {
        super.init()
    }

    func start() {
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: LockedConstants.heartbeatInterval, target: self,
                      selector: #selector(timerFired(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let heartbeat = LockedStore.loadHeartbeat()
        let connected = heartbeat?.isFresh() ?? false
        if connected != isConnected { isConnected = connected }
        let version = connected ? heartbeat?.extensionVersion : nil
        if version != extensionVersion { extensionVersion = version }
    }

    @objc private func timerFired(_ timer: Timer) {
        refresh()
    }
}
