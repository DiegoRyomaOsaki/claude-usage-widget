import Foundation

/// The seven-day history half of the payload, aggregated from Claude Code's own
/// transcripts under `~/.claude/projects`.
///
/// Anthropic's usage endpoint reports percentages against the plan, not token counts, and
/// says nothing about which model spent them. Claude Code writes one JSONL file per
/// conversation, and every assistant turn carries its model plus a `usage` block, so the
/// per-day and per-model breakdown in the large layout comes from here instead.
///
/// The scope this implies is worth stating plainly, and the UI labels it: these numbers
/// cover Claude Code on this Mac. Work done in the claude.ai web app counts against the
/// plan limits above but leaves no transcript here, so it does not appear in the chart.
enum LocalUsage {
    struct Aggregate {
        var days: [DayUsage]
        var models: [ModelUsage]
        var stats: LocalStats
    }

    static let windowDays = 7

    static func aggregate(now: Date = Date(), calendar: Calendar = .current) -> Aggregate {
        let start = calendar.startOfDay(for: now.addingTimeInterval(-Double(windowDays - 1) * 86400))

        var tokensByDayModel: [String: [String: Int]] = [:]
        var tokensByModel: [String: Int] = [:]
        var tokensByHour = [Int](repeating: 0, count: 24)
        var sessions = Set<String>()
        var messages = 0
        // The same assistant turn is written more than once when a request is streamed or
        // retried. Request id plus message id identifies the turn across those repeats.
        var seen = Set<String>()

        let dayKey = DateFormatter()
        dayKey.calendar = calendar
        dayKey.locale = Locale(identifier: "en_US_POSIX")
        dayKey.timeZone = calendar.timeZone
        dayKey.dateFormat = "yyyy-MM-dd"

        for file in transcripts(modifiedSince: start) {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            guard let data = try? handle.readToEnd() else { continue }

            data.split(separator: UInt8(ascii: "\n")).forEach { line in
                // Most lines are user turns and tool results with no usage block. Parsing
                // every one of them costs far more than this substring check skipping them.
                guard line.count > 40, contains(line, "\"usage\"") else { return }
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let timestamp = object["timestamp"] as? String,
                      let date = isoDate(timestamp), date >= start else { return }

                let model = (message["model"] as? String) ?? ""
                // Claude Code logs local bookkeeping turns under this pseudo-model.
                guard !model.isEmpty, model != "<synthetic>" else { return }

                // Request id plus message id identifies one assistant turn. The pair
                // repeats across the streamed and retried copies of that turn, whose
                // timestamps differ — so the timestamp must stay out of this key, or every
                // duplicate is counted again and the totals come out roughly doubled.
                // Lines missing both ids fall back to their own uuid, which never
                // collides and therefore never deduplicates.
                let identity: String
                if let requestId = object["requestId"] as? String, let messageId = message["id"] as? String {
                    identity = "\(requestId)|\(messageId)"
                } else {
                    identity = (object["uuid"] as? String) ?? UUID().uuidString
                }
                guard seen.insert(identity).inserted else { return }

                let total = ["input_tokens", "output_tokens",
                             "cache_creation_input_tokens", "cache_read_input_tokens"]
                    .reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
                guard total > 0 else { return }

                let display = displayName(for: model)
                tokensByDayModel[dayKey.string(from: date), default: [:]][display, default: 0] += total
                tokensByModel[display, default: 0] += total
                tokensByHour[calendar.component(.hour, from: date)] += total
                messages += 1
                if let session = (object["sessionId"] as? String) ?? (object["session_id"] as? String) {
                    sessions.insert(session)
                }
            }
        }

        // One entry per day in the window, including days with no activity, so the chart
        // keeps a stable seven-column shape instead of stretching over a quiet weekend.
        let weekdayLabels = DateFormatter()
        weekdayLabels.calendar = calendar
        weekdayLabels.timeZone = calendar.timeZone
        weekdayLabels.locale = Locale(identifier: "es_ES")
        weekdayLabels.dateFormat = "EEEEE"

        var days: [DayUsage] = []
        for offset in 0..<windowDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let key = dayKey.string(from: date)
            days.append(DayUsage(date: key,
                                 label: weekdayLabels.string(from: date).uppercased(),
                                 byModel: tokensByDayModel[key] ?? [:]))
        }

        let models = tokensByModel
            .map { ModelUsage(name: $0.key, tokens: $0.value) }
            .sorted { $0.tokens > $1.tokens }

        let peakHour = tokensByHour.enumerated().max { $0.element < $1.element }
            .flatMap { $0.element > 0 ? $0.offset : nil }

        let stats = LocalStats(sessions: sessions.count,
                               messages: messages,
                               streakDays: streak(in: days),
                               peakHour: peakHour,
                               totalTokens: tokensByModel.values.reduce(0, +))

        return Aggregate(days: days, models: models, stats: stats)
    }

    /// Consecutive active days ending at the most recent one.
    ///
    /// Capped by the window: a streak longer than seven days reports seven, because
    /// nothing older than that is loaded.
    private static func streak(in days: [DayUsage]) -> Int {
        var count = 0
        for day in days.reversed() {
            // Today being quiet so far should not zero out a run that ended yesterday.
            if day.total == 0 { if count == 0 && day.date == days.last?.date { continue }; break }
            count += 1
        }
        return count
    }

    /// Transcript files that could hold a turn inside the window.
    ///
    /// A file untouched since before the window started cannot contain a newer turn, so
    /// filtering on modification time skips most of the history without reading it.
    private static func transcripts(modifiedSince cutoff: Date) -> [URL] {
        let root = Paths.claudeProjects
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= cutoff else { continue }
            files.append(url)
        }
        return files
    }

    /// `claude-opus-5` → `Opus 5`, `claude-fable-5-1` → `Fable 5.1`,
    /// `claude-haiku-4-5-20251001` → `Haiku 4.5`.
    static func displayName(for model: String) -> String {
        var parts = model
            .replacingOccurrences(of: "claude-", with: "")
            .split(separator: "-")
            .map(String.init)
        // Trailing yyyymmdd snapshot stamps are noise in a legend this narrow.
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard let family = parts.first else { return model }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? String(name) : "\(name) \(version)"
    }

    private static func isoDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static func contains(_ slice: Data.SubSequence, _ needle: String) -> Bool {
        let bytes = Array(needle.utf8)
        guard slice.count >= bytes.count else { return false }
        return slice.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            let limit = raw.count - bytes.count
            if limit < 0 { return false }
            for offset in 0...limit {
                var matched = true
                for index in 0..<bytes.count where base[offset + index] != bytes[index] {
                    matched = false
                    break
                }
                if matched { return true }
            }
            return false
        }
    }
}
