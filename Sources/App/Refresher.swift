import Foundation
import WidgetKit

/// One refresh: read the Keychain, call the usage API, aggregate local transcripts, fold in
/// the status-line feed, write `status.json`, and poke WidgetKit.
///
/// The widget extension does none of this — it is sandboxed and only reads the file the
/// container app leaves for it.
enum Refresher {
    /// How often the API is asked. The session and weekly bars do not wait on this while
    /// Claude Code is in use — `LiveFeed` moves them after every response — so the poll
    /// only has to keep up with the scoped weekly window and with usage on claude.ai.
    /// Polling harder than this earned hour-long runs of HTTP 429.
    static let interval: TimeInterval = 5 * 60

    /// The menu-bar app and the LaunchAgent both refresh on their own clocks. Whichever
    /// comes second inside this window skips, so running both costs no extra requests.
    private static let spacing: TimeInterval = interval - 20

    /// Serialises every read-modify-write of `status.json` inside the app, where a timer,
    /// the folder watcher and a click can all land at once.
    static let queue = DispatchQueue(label: "io.diegopuerto.claudeusage.refresh")

    /// - Parameters:
    ///   - interactive: false when `launchd` drives this, so a Keychain authorization
    ///     prompt fails fast rather than hanging an unattended process.
    ///   - force: a person asked for this refresh. It skips the pacing and any 429
    ///     backoff; a scheduled refresh respects both.
    @discardableResult
    static func refresh(interactive: Bool = true, force: Bool = false) -> UsagePayload {
        let now = Date()
        let previous = StatusStore.read()
        var payload = previous ?? .empty
        var sync = payload.sync ?? SyncState()

        if !force, let last = sync.refreshedAt, now.timeIntervalSince(last) < spacing {
            return payload
        }
        sync.refreshedAt = now

        // The local history does not depend on the network, so it is computed either way
        // and a failed API call still leaves the chart current.
        let local = LocalUsage.aggregate()
        payload.days = local.days
        payload.models = local.models
        payload.stats = local.stats

        if force || (sync.retryAfter ?? .distantPast) <= now {
            fetchLimits(into: &payload, sync: &sync, interactive: interactive, now: now)
        }

        LiveFeed.apply(to: &payload, now: now)
        payload.sync = sync
        publish(payload, replacing: previous)
        return payload
    }

    /// Folds a new status-line snapshot in, without touching the network. Cheap enough to
    /// run on every Claude Code response.
    static func ingestLive() -> UsagePayload? {
        let previous = StatusStore.read()
        var payload = previous ?? .empty
        guard LiveFeed.apply(to: &payload) else { return nil }
        publish(payload, replacing: previous)
        return payload
    }

    private static func fetchLimits(into payload: inout UsagePayload, sync: inout SyncState,
                                    interactive: Bool, now: Date) {
        do {
            let credentials = try Credentials.load(allowInteraction: interactive)
            // A request with a token already known to be dead only adds to the rate limit.
            if credentials.isExpired { throw UsageAPI.Failure.unauthorized }

            let limits = try UsageAPI.fetchLimits(token: credentials.accessToken)
            payload.session = LimitBar.merged(payload.session, limits.session, now: now)
            payload.weeklyAll = LimitBar.merged(payload.weeklyAll, limits.weeklyAll, now: now)
            payload.scoped = limits.scoped
            payload.extra = limits.extra

            let planIsKnown = payload.plan != UsagePayload.empty.plan
            if !planIsKnown || now.timeIntervalSince(sync.planCheckedAt ?? .distantPast) > 24 * 3600 {
                payload.plan = UsageAPI.fetchPlanName(token: credentials.accessToken)
                    ?? UsageAPI.planName(fromTier: credentials.rateLimitTier)
                    ?? payload.plan
                sync.planCheckedAt = now
            }

            payload.fetchedAt = now
            payload.error = nil
            payload.needsLogin = nil
            sync.retryAfter = nil
            sync.throttled = nil
        } catch UsageAPI.Failure.rateLimited(let retryAfter) {
            // Without a Retry-After, back off 5, 10, 20, 40 and then 60 minutes.
            let strikes = (sync.throttled ?? 0) + 1
            let wait = retryAfter ?? min(60 * 60, interval * pow(2, Double(strikes - 1)))
            let until = now.addingTimeInterval(wait)
            sync.throttled = strikes
            sync.retryAfter = until
            payload.error = "Anthropic está limitando las consultas de uso. Reintento a las \(clock(until))."
            payload.needsLogin = nil
            log("429: reintento en \(Int(wait / 60)) min")
        } catch {
            // Keep the last known percentages next to the error: a stale number with a
            // visible warning beats an empty widget.
            payload.error = error.localizedDescription
            payload.needsLogin = isLoginProblem(error) ? true : nil
            log("refresh falló: \(error.localizedDescription)")
        }
    }

    private static func isLoginProblem(_ error: Error) -> Bool {
        switch error {
        case UsageAPI.Failure.unauthorized, Credentials.Failure.notFound: return true
        default: return false
        }
    }

    /// Writes the payload, and reloads the widget only when something it draws changed.
    ///
    /// WidgetKit rations reloads for an app that is not in the foreground, and a menu-bar
    /// accessory never is. Reloading on every poll spent that ration overnight on
    /// identical snapshots and left none for the afternoon, when the numbers move.
    private static func publish(_ payload: UsagePayload, replacing previous: UsagePayload?) {
        do {
            try StatusStore.write(payload)
        } catch {
            log("no pude escribir status.json: \(error.localizedDescription)")
        }
        if previous.map(widgetSignature) != widgetSignature(payload) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// What the widget layouts can show, at the precision they show it. The countdowns
    /// tick from timeline entries and need no reload of their own.
    private static func widgetSignature(_ p: UsagePayload) -> String {
        func bar(_ b: LimitBar?) -> String {
            guard let b else { return "-" }
            return "\(Int(b.percent.rounded()))@\(Int((b.resetsAt?.timeIntervalSince1970 ?? 0) / 60))"
        }
        return [
            p.plan, String(p.isStale), bar(p.session), bar(p.weeklyAll),
            p.scoped.map { "\($0.name)=\(bar($0.bar))" }.joined(separator: ","),
            p.days.map { "\($0.date):\(Fmt.tokens($0.total))" }.joined(separator: ","),
            p.models.map { "\($0.name):\(Fmt.tokens($0.tokens))" }.joined(separator: ","),
            "\(p.stats.sessions)/\(p.stats.streakDays)/\(p.stats.peakHour ?? -1)",
        ].joined(separator: "|")
    }

    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
