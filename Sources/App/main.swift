import AppKit
import SwiftUI

// `--refresh` is how the LaunchAgent drives this binary. It must not touch AppKit: the
// agent runs in a background session with no window server, and bringing up
// NSApplication there would either fail or leave a process behind every five minutes.
if CommandLine.arguments.contains("--refresh") {
    let payload = Refresher.refresh(interactive: false)
    if let error = payload.error {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
    exit(0)
}

/// Menu-bar accessory: a tinted spark plus the session percentage, and the prototype's
/// popover behind it.
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let model = UsageModel()
    private var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarPopover(model: model))

        // First run: install the background agent so the widget has data without the user
        // having to find a toggle first. Turning it off in the popover sticks.
        if !LaunchAgent.isInstalled { try? LaunchAgent.install() }
        model.backgroundRefresh = LaunchAgent.isInstalled

        render()
        model.refresh()

        // The LaunchAgent writes status.json from its own process, so the menu bar has to
        // re-read the file rather than rely on its own refreshes.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.model.reload()
            self?.render()
        }

        // UsageModel drives a SwiftUI popover; the menu-bar button is AppKit and has no
        // way to observe it, so the model calls back whenever the payload changes.
        model.onChange = { [weak self] in self?.render() }
    }

    /// Spark tinted by the worst window, then the session percentage.
    private func render() {
        guard let button = statusItem.button else { return }
        let percent = model.payload.session?.percent ?? model.worstPercent
        let color = NSColor(Theme.color(forPercent: model.worstPercent))

        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Uso de Claude")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        button.image = image
        button.imagePosition = .imageLeading

        let title = model.payload.fetchedAt == .distantPast ? " —" : " \(Int(percent.rounded()))%"
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ])
        button.toolTip = model.payload.error ?? "Sesión \(Int(percent.rounded()))% · actualizado \(Fmt.ago(model.payload.fetchedAt))"
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.reload()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Actualizar ahora", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Ajustes de uso en claude.ai", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Abrir carpeta de datos", action: #selector(openDataFolder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // A menu assigned to the status item swallows the button action, so it is removed
        // straight after showing to keep left-click opening the popover.
        statusItem.menu = nil
    }

    @objc private func refreshNow() { model.refresh() }

    @objc private func openSettings() {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
    }

    @objc private func openDataFolder() {
        try? FileManager.default.createDirectory(at: Paths.localSupport, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Paths.localSupport)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
