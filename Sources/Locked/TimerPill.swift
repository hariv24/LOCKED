import AppKit
import Foundation

/// Floating, non-activating pill at the top-center of the main screen showing the remaining time.
@MainActor
final class TimerPillController: NSObject {
    static let shared = TimerPillController()

    private static let size = NSSize(width: 124, height: 30)

    private var panel: NSPanel?
    private var pillView: TimerPillView?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    func show(remaining: TimeInterval) {
        if panel == nil {
            buildPanel()
        }
        update(remaining: remaining)
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func update(remaining: TimeInterval) {
        pillView?.setText(formatCountdown(remaining))
    }

    private func buildPanel() {
        let rect = NSRect(origin: .zero, size: Self.size)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true

        let view = TimerPillView(frame: rect)
        view.onClick = {
            MainWindowRouter.shared.showMain()
        }
        panel.contentView = view

        self.panel = panel
        self.pillView = view
    }

    private func positionPanel() {
        guard let panel else { return }
        // The first screen is the one with the menu bar.
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 6)
        panel.setFrameOrigin(origin)
    }

    @objc private func screensChanged(_ note: Notification) {
        positionPanel()
    }
}

final class TimerPillView: NSView {
    var onClick: (@MainActor () -> Void)?
    private let label = NSTextField(labelWithString: "--:--")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.88).cgColor
        layer?.cornerRadius = frameRect.height / 2
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.18).cgColor

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = "Locked session in progress. Click to open Locked."
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setText(_ text: String) {
        if label.stringValue != text {
            label.stringValue = text
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Route every click inside the pill to this view (not the label).
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
