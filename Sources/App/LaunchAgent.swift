import Foundation

/// The five-minute background poll, as a user LaunchAgent.
///
/// WidgetKit will not let an extension fetch on its own schedule, and the container app
/// is a menu-bar accessory the user may quit. `launchd` running `--refresh` keeps
/// `status.json` current either way.
enum LaunchAgent {
    static let label = "io.diegopuerto.claudeusage.refresh"

    static var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// Path of the running binary, so the agent survives being installed from either
    /// `/Applications` or `~/Applications`.
    private static var executablePath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    }

    static func install(intervalMinutes: Int = 5) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "--refresh"],
            "StartInterval": max(60, intervalMinutes * 60),
            // Without this the first refresh waits a full interval after login.
            "RunAtLoad": true,
            "ProcessType": "Background",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
        bootout()
        bootstrap()
    }

    static func uninstall() {
        bootout()
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static var domain: String { "gui/\(getuid())" }

    private static func bootstrap() {
        _ = launchctl(["bootstrap", domain, plistURL.path])
    }

    private static func bootout() {
        _ = launchctl(["bootout", "\(domain)/\(label)"])
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
