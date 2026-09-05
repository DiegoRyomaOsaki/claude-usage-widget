import AppKit
import SwiftUI

/// The dropdown behind the menu-bar item.
///
/// This is a floating `NSPanel` rather than an `NSPopover` on purpose. A popover anchors
/// itself flush against the status item and draws a pointer into it, which on the current
/// menu bar leaves the panel sitting on top of the bar instead of below it. Menu-bar apps
/// that look right — iStat, Stats — use a detached panel placed a few points under the bar,
/// and that is what this reproduces: rounded on all four corners, its own shadow, and a
/// visible gap above it.
final class UsagePanel: NSPanel {
    /// Distance between the bottom of the menu bar and the top of the panel.
    static let menuBarGap: CGFloat = 8
    static let cornerRadius: CGFloat = 14

    init(rootView: some View) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 420),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        // Above normal windows and full-screen apps, like every other menu-bar dropdown.
        level = .statusBar
        // The rounded corners are drawn by the content, so the window itself is clear and
        // only contributes the shadow.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // Without this the panel vanishes the moment focus moves, including to its own
        // click-through targets.
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: AnyView(
            rootView
                .clipShape(RoundedRectangle(cornerRadius: UsagePanel.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: UsagePanel.cornerRadius, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
        ))
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
    }

    /// A borderless panel refuses key status by default, which would leave the buttons
    /// inside it dead.
    override var canBecomeKey: Bool { true }
}

/// Shows, hides and positions the panel, and closes it on a click elsewhere.
final class UsagePanelController {
    private let panel: UsagePanel
    private var outsideClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    var isVisible: Bool { panel.isVisible }

    init(rootView: some View) {
        panel = UsagePanel(rootView: rootView)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.hide() }
    }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func toggle(from button: NSStatusBarButton) {
        isVisible ? hide() : show(from: button)
    }

    func show(from button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }

        // Let SwiftUI settle on a height before asking where the top edge should go.
        panel.layoutIfNeeded()
        if let fitting = panel.contentView?.fittingSize, fitting.height > 0 {
            panel.setContentSize(fitting)
        }
        let size = panel.frame.size

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main

        // Centred under the status item, then nudged back inside the screen so an item
        // near the right edge does not push the panel off it.
        var x = buttonRect.midX - size.width / 2
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + UsagePanel.menuBarGap),
                    visible.maxX - size.width - UsagePanel.menuBarGap)
        }
        let y = buttonRect.minY - UsagePanel.menuBarGap - size.height

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        removeOutsideClickMonitor()
    }

    /// A transient popover dismisses itself on an outside click; a panel has to be told.
    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in self?.hide() }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}
