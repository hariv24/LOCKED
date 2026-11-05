// LockedBridge: Chrome native messaging host for Locked (host name `app.locked.bridge`).
//
// Chrome launches this binary when the extension calls `connectNative` and talks to it over
// stdin/stdout (4-byte little-endian length + UTF-8 JSON). stdout is the protocol channel:
// never print() anything. All logging goes to stderr.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import LockedBridgeCore
import LockedShared

func log(_ message: String) {
    FileHandle.standardError.write(Data("LockedBridge: \(message)\n".utf8))
}

// A closed stdout must surface as a write error, not kill us with SIGPIPE.
signal(SIGPIPE, SIG_IGN)

// MARK: Output

let stdoutLock = NSLock()

/// Writes one framed message to stdout. FileHandle writes go straight to the fd (unbuffered).
func writeFrame(_ payload: Data) {
    let framed: Data
    do {
        framed = try NativeMessaging.frame(payload)
    } catch {
        log("dropping outgoing message: \(error)")
        return
    }
    stdoutLock.lock()
    defer { stdoutLock.unlock() }
    do {
        try FileHandle.standardOutput.write(contentsOf: framed)
        fflush(stdout)  // no-op unless something wrote via stdio; keeps the channel clean
    } catch {
        // Chrome has gone away.
        log("stdout write failed (\(error)); exiting")
        exit(0)
    }
}

// MARK: Controller

let queue = DispatchQueue(label: "app.locked.bridge.state")
var heartbeatErrorLogged = false

let controller = BridgeController(
    writeHeartbeat: { hb in
        do {
            try LockedStore.saveHeartbeat(hb)
            heartbeatErrorLogged = false
        } catch {
            if !heartbeatErrorLogged {
                log("failed to write heartbeat: \(error)")
                heartbeatErrorLogged = true
            }
        }
    },
    send: { state in
        do {
            writeFrame(try state.encoded())
        } catch {
            log("failed to encode state: \(error)")
        }
    }
)

// MARK: Input (background thread)

func readLoop() {
    var decoder = FrameDecoder()
    let bufferSize = 64 * 1024
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
    defer { buffer.deallocate() }

    while true {
        let n = read(STDIN_FILENO, buffer, bufferSize)
        if n == 0 {
            // Chrome closed the pipe: the extension disconnected.
            if decoder.pendingByteCount > 0 { log("EOF with \(decoder.pendingByteCount) bytes of a partial frame") }
            exit(0)
        }
        if n < 0 {
            if errno == EINTR { continue }
            log("stdin read failed: errno \(errno)")
            exit(1)
        }
        let messages: [Data]
        do {
            messages = try decoder.append(Data(bytes: buffer, count: n))
        } catch {
            log("corrupt input stream: \(error)")
            exit(1)
        }
        for payload in messages {
            guard let message = IncomingMessage.parse(payload) else {
                log("ignoring non-JSON-object message (\(payload.count) bytes)")
                continue
            }
            queue.async { controller.handle(message) }
        }
    }
}

// MARK: Timers

func makeTimer(interval: TimeInterval, handler: @escaping () -> Void) -> DispatchSourceTimer {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
    timer.setEventHandler(handler: handler)
    timer.resume()
    return timer
}

log("started (pid \(getpid()))")

#if canImport(Darwin)
// Opt out of App Nap / timer coalescing: if Chrome is in the background, a throttled heartbeat
// timer could let bridge-heartbeat.json go stale (> 6s) and make the app hide Chrome.
let napActivity: NSObjectProtocol? = ProcessInfo.processInfo.beginActivity(
    options: .userInitiatedAllowingIdleSystemSleep, reason: "Locked bridge heartbeat")
#else
let napActivity: NSObjectProtocol? = nil
#endif

// Chrome only launches us for a connected extension, so we count as connected from the start.
queue.async { controller.heartbeat() }

let pollTimer = makeTimer(interval: 1) { controller.poll() }
let heartbeatTimer = makeTimer(interval: LockedConstants.heartbeatInterval) { controller.heartbeat() }

Thread.detachNewThread { readLoop() }

withExtendedLifetime((pollTimer, heartbeatTimer, napActivity)) {
    dispatchMain()
}
