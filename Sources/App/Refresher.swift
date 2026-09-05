import Foundation
import WidgetKit

/// One refresh: read the Keychain, call the usage API, aggregate local transcripts, write
/// `status.json`, and poke WidgetKit.
///
/// The widget extension does none of this — it is sandboxed and only reads the file the
/// container app leaves for it.
enum Refresher {
    /// - Parameter interactive: false when `launchd` drives this, so a Keychain
    ///   authorization prompt fails fast rather than hanging an unattended process.
    @discardableResult
    static func refresh(interactive: Bool = true) -> UsagePayload {
        let previous = StatusStore.read()
        var payload = previous ?? .empty
        payload.error = nil

        // The local history does not depend on the network, so it is computed either way
        // and a failed API call still leaves the chart current.
        let local = LocalUsage.aggregate()
        payload.days = local.days
        payload.models = local.models
        payload.stats = local.stats

        do {
            let credentials = try Credentials.load(allowInteraction: interactive)
            let limits = try UsageAPI.fetchLimits(token: credentials.accessToken)
            payload.session = limits.session
            payload.weeklyAll = limits.weeklyAll
            payload.scoped = limits.scoped
            payload.extra = limits.extra
            payload.plan = UsageAPI.fetchPlanName(token: credentials.accessToken)
                ?? UsageAPI.planName(fromTier: credentials.rateLimitTier)
                ?? "Claude"
        } catch {
            // Keep the last known percentages next to the error: a stale number with a
            // visible warning beats an empty widget.
            payload.error = error.localizedDescription
            log("refresh falló: \(error.localizedDescription)")
        }

        payload.fetchedAt = Date()
        do {
            try StatusStore.write(payload)
        } catch {
            log("no pude escribir status.json: \(error.localizedDescription)")
        }
        WidgetCenter.shared.reloadAllTimelines()
        return payload
    }

    static func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = Paths.logFile
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
