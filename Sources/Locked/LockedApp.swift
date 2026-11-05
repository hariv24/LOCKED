import AppKit
import SwiftUI
import LockedShared

/// Scene id of the single main window.
let mainWindowId = "main"

@main
struct LockedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Locked", id: mainWindowId) {
            RootView()
                .environmentObject(SessionManager.shared)
                .environmentObject(BridgeStatus.shared)
                .environmentObject(SetupModel.shared)
        }
        .defaultSize(width: 760, height: 860)
        .commands {
            // Single-window app: no "New Window" command.
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set when the user logs out / shuts down / restarts, so we don't block that during a session.
    /// The session file stays on disk and is resumed after the next login (the LaunchAgent relaunches us).
    private var allowTerminationForPowerOff = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? LockedPaths.ensureBaseDir()
        ExtensionInstaller.install()
        NativeHostInstaller.install()
        Notifier.configure()
        BridgeStatus.shared.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillPowerOff(_:)),
            name: NSWorkspace.willPowerOffNotification,
            object: nil)

        SessionManager.shared.resumeOnLaunch()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if SessionManager.shared.isActive && !allowTerminationForPowerOff {
            NSSound.beep()
            MainWindowRouter.shared.showMain()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainWindowRouter.shared.showMain()
        }
        return true
    }

    @objc private func workspaceWillPowerOff(_ note: Notification) {
        allowTerminationForPowerOff = true
        if SessionManager.shared.isActive {
            // Otherwise the watchdog could `open -a` a fresh Locked during logout, which never got this
            // notification and would cancel the logout. The plist stays, so RunAtLoad brings it back at next login.
            LaunchAgentInstaller.unloadKeepingPlist()
        }
        // If another app cancels the logout/shutdown, go back to refusing quit.
        perform(#selector(resetPowerOffFlag), with: nil, afterDelay: 120)
    }

    @objc private func resetPowerOffFlag() {
        allowTerminationForPowerOff = false
        // The logout was cancelled: put the watchdog back.
        if SessionManager.shared.isActive {
            LaunchAgentInstaller.install()
        }
    }
}

/// Brings the main window back from anywhere (timer pill, app blocker, dock reopen).
@MainActor
final class MainWindowRouter {
    static let shared = MainWindowRouter()

    /// Captured from the SwiftUI environment once the root view appears.
    var openWindowAction: OpenWindowAction?
    weak var window: NSWindow?

    private init() {}

    func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let window, window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if let action = openWindowAction {
            // For a `Window` scene this opens it, or brings it to the front if already open.
            action(id: mainWindowId)
        } else if let window {
            window.makeKeyAndOrderFront(nil)
        } else if let any = NSApp.windows.first(where: { $0.canBecomeMain }) {
            any.makeKeyAndOrderFront(nil)
        }
    }
}

/// Reports the NSWindow hosting a SwiftUI view.
@MainActor
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindow = onWindow
    }
}

final class WindowReportingView: NSView {
    var onWindow: (@MainActor (NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindow?(window)
        }
    }
}
