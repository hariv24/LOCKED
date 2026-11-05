// LockedWatchdog: run by the `app.locked.watchdog` LaunchAgent during a session.
//
//   LockedWatchdog --app /Applications/Locked.app
//
// Every 2s: if session.json is missing or expired, exit(0) (launchd's KeepAlive
// {SuccessfulExit: false} then leaves us stopped). Otherwise, if Locked isn't running,
// relaunch it with `open -a`.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import LockedShared

func log(_ message: String) {
    FileHandle.standardError.write(Data("LockedWatchdog: \(message)\n".utf8))
}

let checkInterval: TimeInterval = 2
/// After relaunching, give the app time to come up before trying again.
let relaunchGrace: TimeInterval = 8
let pgrepPath = "/usr/bin/pgrep"
let openPath = "/usr/bin/open"

// MARK: Arguments

func parseAppPath(_ args: [String]) -> String? {
    var i = 0
    while i < args.count {
        let a = args[i]
        if a == "--app", i + 1 < args.count { return args[i + 1] }
        if a.hasPrefix("--app=") { return String(a.dropFirst("--app=".count)) }
        i += 1
    }
    return nil
}

guard var appPath = parseAppPath(Array(CommandLine.arguments.dropFirst())), !appPath.isEmpty else {
    log("usage: LockedWatchdog --app <path to Locked.app>")
    exit(64)  // EX_USAGE
}
while appPath.count > 1, appPath.hasSuffix("/") { appPath.removeLast() }

// MARK: Process helpers

/// Escapes POSIX extended-regex metacharacters (pgrep patterns are EREs).
func regexEscaped(_ s: String) -> String {
    let special: Set<Character> = ["\\", ".", "[", "]", "(", ")", "{", "}", "*", "+", "?", "|", "^", "$"]
    var out = ""
    for c in s {
        if special.contains(c) { out.append("\\") }
        out.append(c)
    }
    return out
}

/// Runs a tool and returns its exit status, or nil if it couldn't be launched.
func run(_ path: String, _ arguments: [String]) -> Int32? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = arguments
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
    } catch {
        log("failed to run \(path): \(error)")
        return nil
    }
    p.waitUntilExit()
    return p.terminationStatus
}

/// The app's main executable, matched as the whole argv[0] (optionally followed by arguments).
let pgrepPattern = regexEscaped(appPath + "/Contents/MacOS/Locked") + "( |$)"

/// true = running, false = not running, nil = couldn't tell.
func isAppRunning() -> Bool? {
    switch run(pgrepPath, ["-f", pgrepPattern]) {
    case 0: return true
    case 1: return false
    case let status:
        log("pgrep failed with status \(status.map(String.init) ?? "n/a")")
        return nil
    }
}

func sessionIsActive() -> Bool {
    guard let session = LockedStore.loadSession() else { return false }
    return session.isActive()
}

// MARK: Main loop

log("watching \(appPath)")
var lastRelaunch = Date.distantPast

while true {
    guard sessionIsActive() else {
        log("no active session; exiting")
        exit(0)
    }
    if Date().timeIntervalSince(lastRelaunch) >= relaunchGrace, isAppRunning() == false {
        log("Locked is not running; relaunching")
        lastRelaunch = Date()
        if let status = run(openPath, ["-a", appPath]), status != 0 {
            log("open -a exited with status \(status)")
        }
    }
    Thread.sleep(forTimeInterval: checkInterval)
}
