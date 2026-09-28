import Foundation

/// The session and weekly windows as Claude Code itself last saw them.
///
/// Claude Code hands its status-line command a JSON blob after every response, and for a
/// Pro or Max account that blob carries `rate_limits.five_hour` and `rate_limits.seven_day`
/// straight from the API's response headers. One line in the user's status-line script
/// copies that object into `live.json`:
///
///     {"at": 1790608067.73, "rate_limits": {"five_hour": {"used_percentage": 23.5,
///      "resets_at": 1790622000}, "seven_day": {...}}}
///
/// That turns the widget's lag from "next poll, if the API is not rate limiting" into
/// "the next Claude Code response", with no request and no token involved. The scoped
/// weekly window (Fable today) is not in that blob, so the API poll still fills it in.
enum LiveFeed {
    struct Snapshot {
        var at: Date
        var session: LimitBar?
        var weeklyAll: LimitBar?
    }

    static func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: Paths.liveFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = json["at"] as? Double,
              let limits = json["rate_limits"] as? [String: Any] else { return nil }
        return Snapshot(at: Date(timeIntervalSince1970: at),
                        session: bar(limits["five_hour"]),
                        weeklyAll: bar(limits["seven_day"]))
    }

    /// Folds the latest snapshot into `payload`. Returns false when there was nothing new.
    @discardableResult
    static func apply(to payload: inout UsagePayload, now: Date = Date()) -> Bool {
        guard let snapshot = read() else { return false }
        if let liveAt = payload.liveAt, snapshot.at <= liveAt { return false }
        payload.session = LimitBar.merged(payload.session, snapshot.session, now: now)
        payload.weeklyAll = LimitBar.merged(payload.weeklyAll, snapshot.weeklyAll, now: now)
        payload.liveAt = snapshot.at
        return true
    }

    private static func bar(_ value: Any?) -> LimitBar? {
        guard let dict = value as? [String: Any] else { return nil }
        let percent = (dict["used_percentage"] as? NSNumber)?.doubleValue
        guard let percent else { return nil }
        let reset = (dict["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return LimitBar(percent: percent, resetsAt: reset)
    }
}

extension LimitBar {
    /// Two readings of one window can disagree on the reset time by a second or so.
    private static let sameWindow: TimeInterval = 5 * 60

    /// Combines two readings of the same kind of window without ever going backwards.
    ///
    /// Several Claude Code sessions write the same `live.json`, and an idle one can
    /// re-run its status line hours after its last API response, stamping old numbers
    /// with a fresh time. Timestamps therefore cannot decide which reading wins. Usage
    /// inside one window only grows, though, so: a later reset time is a new window and
    /// replaces the old one, an earlier one is stale and is dropped, and the same window
    /// keeps the higher percentage.
    static func merged(_ current: LimitBar?, _ incoming: LimitBar?, now: Date) -> LimitBar? {
        guard let incoming else { return current }
        guard let current, let currentReset = current.resetsAt, currentReset > now else { return incoming }
        guard let incomingReset = incoming.resetsAt else { return incoming }
        if incomingReset > currentReset.addingTimeInterval(sameWindow) { return incoming }
        if incomingReset < currentReset.addingTimeInterval(-sameWindow) { return current }
        return LimitBar(percent: max(current.percent, incoming.percent), resetsAt: incomingReset)
    }
}

/// Calls back when something in the app's data folder changes.
///
/// The status-line line writes `live.json` by renaming a temporary file into place, which
/// a watch on the file itself would lose track of. Watching the directory survives that,
/// at the price of also firing on this app's own writes; `LiveFeed.apply` ignores a
/// snapshot it has already seen, so those cost one read and nothing more.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init?(url: URL, onChange: @escaping () -> Void) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: .write,
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            // A burst of renames is one update.
            self?.pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    deinit { source?.cancel() }
}
