import Foundation
import LockedShared

/// Copies the bundled Chrome extension to `~/Library/Application Support/Locked/ChromeExtension`
/// so the user can "Load unpacked" from a stable location.
enum ExtensionInstaller {
    static var bundledExtensionURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension", isDirectory: true)
    }

    @discardableResult
    static func install() -> Bool {
        let fm = FileManager.default
        guard let source = bundledExtensionURL, fm.fileExists(atPath: source.path) else {
            NSLog("Locked: bundled ChromeExtension folder not found in app resources")
            return false
        }
        let destination = LockedPaths.extensionDir
        do {
            try LockedPaths.ensureBaseDir()
            guard fm.fileExists(atPath: destination.path) else {
                try fm.copyItem(at: source, to: destination)
                return true
            }
            // Chrome has this folder loaded: leave it alone if it's already up to date.
            if folderContentsEqual(source, destination) {
                return true
            }
            // Copy next to it, then swap it in atomically so Chrome never sees a half-written folder.
            let staging = destination.deletingLastPathComponent()
                .appendingPathComponent("ChromeExtension.staging", isDirectory: true)
            if fm.fileExists(atPath: staging.path) {
                try fm.removeItem(at: staging)
            }
            try fm.copyItem(at: source, to: staging)
            let replaced: URL?
            do {
                replaced = try fm.replaceItemAt(destination, withItemAt: staging)
            } catch {
                try? fm.removeItem(at: staging)
                throw error
            }
            guard replaced != nil else {
                try? fm.removeItem(at: staging)
                NSLog("Locked: failed to replace Chrome extension folder")
                return false
            }
            return true
        } catch {
            NSLog("Locked: failed to install Chrome extension: %@", String(describing: error))
            return false
        }
    }

    /// True if both folders hold the same relative paths (files and subfolders) and every file has the same bytes.
    static func folderContentsEqual(_ a: URL, _ b: URL) -> Bool {
        let fm = FileManager.default
        guard let aPaths = try? fm.subpathsOfDirectory(atPath: a.path),
              let bPaths = try? fm.subpathsOfDirectory(atPath: b.path),
              aPaths.count == bPaths.count,
              Set(aPaths) == Set(bPaths) else { return false }
        for relative in aPaths {
            let aPath = a.appendingPathComponent(relative).path
            let bPath = b.appendingPathComponent(relative).path
            var aIsDir: ObjCBool = false
            var bIsDir: ObjCBool = false
            guard fm.fileExists(atPath: aPath, isDirectory: &aIsDir),
                  fm.fileExists(atPath: bPath, isDirectory: &bIsDir),
                  aIsDir.boolValue == bIsDir.boolValue else { return false }
            if aIsDir.boolValue { continue }
            guard let aData = fm.contents(atPath: aPath),
                  let bData = fm.contents(atPath: bPath),
                  aData == bData else { return false }
        }
        return true
    }
}

/// Helper executables sit next to the app's own executable (Locked.app/Contents/MacOS).
private func helperExecutableURL(named name: String) -> URL {
    let dir = Bundle.main.executableURL?.deletingLastPathComponent()
        ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
    return dir.appendingPathComponent(name)
}

/// Writes Chrome's native messaging host manifest pointing at our bundled LockedBridge.
enum NativeHostInstaller {
    static var bridgeExecutableURL: URL {
        helperExecutableURL(named: "LockedBridge")
    }

    @discardableResult
    static func install() -> Bool {
        let manifest: [String: Any] = [
            "name": LockedConstants.nativeHostName,
            "description": "Locked bridge",
            "path": bridgeExecutableURL.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(LockedConstants.extensionId)/"],
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: manifest,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            let url = LockedPaths.nativeHostManifest
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("Locked: failed to install native host manifest: %@", String(describing: error))
            return false
        }
    }
}

/// Installs/removes the watchdog LaunchAgent (`app.locked.watchdog`).
enum LaunchAgentInstaller {
    static var watchdogExecutableURL: URL {
        helperExecutableURL(named: "LockedWatchdog")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: LockedPaths.launchAgentPlist.path)
    }

    private static var domainTarget: String { "gui/\(getuid())" }
    private static var serviceTarget: String { "\(domainTarget)/\(LockedConstants.launchAgentLabel)" }

    /// Writes the plist and makes sure the job is loaded and running.
    /// Safe to call repeatedly (session start and session resume both call it).
    static func install() {
        let appPath = Bundle.main.bundleURL.path
        let plist: [String: Any] = [
            "Label": LockedConstants.launchAgentLabel,
            "ProgramArguments": [watchdogExecutableURL.path, "--app", appPath],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
        ]
        let plistChanged: Bool
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            let url = LockedPaths.launchAgentPlist
            // Compare before writing: a loaded job keeps running its old arguments until it's reloaded.
            plistChanged = (try? Data(contentsOf: url)) != data
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Locked: failed to write LaunchAgent plist: %@", String(describing: error))
            return
        }

        if isLoaded {
            if plistChanged {
                // Loaded from a stale plist (e.g. the app moved): reload it so the new arguments apply.
                launchctl(["bootout", serviceTarget])
                bootstrap()
            } else {
                // Already loaded (e.g. we were relaunched by it). Start it if it had exited; no-op if running.
                launchctl(["kickstart", serviceTarget])
            }
        } else {
            // Errors like "service already loaded" are ignored on purpose.
            launchctl(["bootstrap", domainTarget, LockedPaths.launchAgentPlist.path])
        }
    }

    /// Bootstraps the plist, retrying once: right after a bootout launchd can briefly refuse it.
    private static func bootstrap() {
        let arguments = ["bootstrap", domainTarget, LockedPaths.launchAgentPlist.path]
        if launchctl(arguments, logFailures: false).status != 0 {
            Thread.sleep(forTimeInterval: 0.5)
            launchctl(arguments)
        }
    }

    static func uninstall() {
        launchctl(["bootout", serviceTarget])
        LockedStore.delete(LockedPaths.launchAgentPlist)
    }

    /// Stops the watchdog job but keeps the plist, so launchd loads it again at the next login (RunAtLoad).
    /// Used at logout/shutdown, where a relaunched Locked would otherwise refuse to quit.
    static func unloadKeepingPlist() {
        launchctl(["bootout", serviceTarget])
    }

    /// True if launchd knows about the job in the user's GUI domain.
    static var isLoaded: Bool {
        launchctl(["print", serviceTarget], logFailures: false).status == 0
    }

    @discardableResult
    private static func launchctl(_ arguments: [String], logFailures: Bool = true) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            NSLog("Locked: could not run launchctl: %@", String(describing: error))
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        // Don't use waitUntilExit(): it spins the main run loop and could re-enter our timers.
        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.005)
        }
        let output = String(data: data, encoding: .utf8) ?? ""
        if logFailures && process.terminationStatus != 0 {
            NSLog("Locked: launchctl %@ exited %d: %@",
                  arguments.joined(separator: " "), process.terminationStatus, output)
        }
        return (process.terminationStatus, output)
    }
}
