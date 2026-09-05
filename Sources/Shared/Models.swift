import Foundation

/// Everything the widget draws, as written by the container app into `status.json`.
///
/// The extension never talks to the network or the Keychain, so this struct is the whole
/// contract between the two processes. Every field is optional or defaulted: a payload
/// written while the API was unreachable still renders, just with fewer numbers.
struct UsagePayload: Codable {
    var fetchedAt: Date
    /// "Max (5x)" — derived from the OAuth profile's rate limit tier.
    var plan: String
    /// The five-hour rolling window. `nil` while the API has never answered.
    var session: LimitBar?
    /// The seven-day, all-models window.
    var weeklyAll: LimitBar?
    /// Model-scoped weekly windows, in the order the API returned them.
    ///
    /// The API does not name a fixed model here: it returns `weekly_scoped` entries whose
    /// `scope.model.display_name` is whatever model currently carries its own weekly
    /// budget — Opus once, Fable today. Reading the name off the payload means the widget
    /// keeps being right when that changes, with no rebuild.
    var scoped: [ScopedLimit]
    /// Pay-as-you-go spend, surfaced only when the account has actually spent something.
    var extra: ExtraUsage?
    /// Local Claude Code token history, newest last. Seven entries when the machine has
    /// seven days of transcripts.
    var days: [DayUsage]
    /// Per-model totals across the same seven days, largest first.
    var models: [ModelUsage]
    var stats: LocalStats
    /// Set when the last refresh failed; the previous numbers are kept alongside it.
    var error: String?

    static let empty = UsagePayload(fetchedAt: .distantPast, plan: "Claude", session: nil,
                                    weeklyAll: nil, scoped: [], extra: nil, days: [],
                                    models: [], stats: .zero, error: nil)
}

/// One usage window: a percentage and when it rolls over.
struct LimitBar: Codable {
    var percent: Double
    var resetsAt: Date?

    var fraction: Double { min(1, max(0, percent / 100)) }
}

struct ScopedLimit: Codable {
    /// "Fable", "Opus" — straight from `scope.model.display_name`.
    var name: String
    var bar: LimitBar
}

struct ExtraUsage: Codable {
    var isEnabled: Bool
    var usedCredits: Double
    var monthlyLimit: Double
    var currency: String

    var hasSpend: Bool { usedCredits > 0 }
}

/// Tokens attributable to one calendar day, split by model.
struct DayUsage: Codable, Identifiable {
    /// `yyyy-MM-dd` in the machine's own time zone — the day the user experienced.
    var date: String
    /// "Mon", "Tue" … for the axis under the sparkline.
    var label: String
    var byModel: [String: Int]

    var id: String { date }
    var total: Int { byModel.values.reduce(0, +) }
}

struct ModelUsage: Codable, Identifiable {
    /// Display form: "Opus 5", not "claude-opus-5".
    var name: String
    var tokens: Int

    var id: String { name }
}

/// Counts derived from the same seven days of transcripts as `days` and `models`.
struct LocalStats: Codable {
    var sessions: Int
    var messages: Int
    /// Consecutive days with activity, counting back from today.
    var streakDays: Int
    /// Hour of day with the most tokens, 0–23, or nil when there is nothing to rank.
    var peakHour: Int?
    var totalTokens: Int

    static let zero = LocalStats(sessions: 0, messages: 0, streakDays: 0, peakHour: nil, totalTokens: 0)

    var peakHourLabel: String {
        guard let peakHour else { return "—" }
        let suffix = peakHour < 12 ? "AM" : "PM"
        let hour12 = peakHour % 12 == 0 ? 12 : peakHour % 12
        return "\(hour12) \(suffix)"
    }
}

// MARK: - Formatting shared by every layout

enum Fmt {
    /// "2h 41m", "2d 6h" — the reset countdown, in the prototype's shape.
    static func countdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "ahora" }
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }

    /// "561.4M", "12.3K" — token counts, which run from thousands to hundreds of millions.
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        if value >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return "\(count)"
    }

    /// "5.984" with the locale's own grouping separator.
    static func count(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// "hace 3 min" for the footer's freshness line.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 0 || date == .distantPast { return "nunca" }
        if seconds < 60 { return "ahora" }
        if seconds < 3600 { return "hace \(seconds / 60) min" }
        if seconds < 86400 { return "hace \(seconds / 3600) h" }
        return "hace \(seconds / 86400) d"
    }
}

// MARK: - Derived values the layouts read

extension UsagePayload {
    /// The window closest to its ceiling. The header dot and the menu-bar tint follow this
    /// rather than the session alone, so a nearly-spent weekly budget still reads as a
    /// warning on a quiet afternoon.
    var worstPercent: Double {
        var values = [session?.percent ?? 0, weeklyAll?.percent ?? 0]
        values.append(contentsOf: scoped.map(\.bar.percent))
        return values.max() ?? 0
    }

    /// True before the first successful refresh — the widget can be added to the desktop
    /// before the app has ever run.
    var isStale: Bool { fetchedAt == .distantPast }

    /// Shown in the widget gallery, where no real payload exists yet. The numbers match
    /// the design prototype so the gallery preview looks like the finished widget.
    static var preview: UsagePayload {
        let now = Date()
        let models = [
            ModelUsage(name: "Opus 5", tokens: 561_400_000),
            ModelUsage(name: "Fable 5", tokens: 52_300_000),
            ModelUsage(name: "Sonnet 5", tokens: 20_900_000),
        ]
        let shape: [[Int]] = [[58_000_000, 0, 0], [0, 0, 0], [38_200_000, 0, 0],
                              [64_500_000, 47_400_000, 11_900_000], [257_300_000, 0, 8_300_000],
                              [131_600_000, 0, 800_000], [11_800_000, 4_900_000, 0]]
        let labels = ["L", "M", "X", "J", "V", "S", "D"]
        let days = (0..<7).map { index in
            DayUsage(date: "preview-\(index)",
                     label: labels[index],
                     byModel: Dictionary(uniqueKeysWithValues: zip(models.map(\.name), shape[index])))
        }
        return UsagePayload(
            fetchedAt: now,
            plan: "Max (5x)",
            session: LimitBar(percent: 40, resetsAt: now.addingTimeInterval(2 * 3600 + 41 * 60)),
            weeklyAll: LimitBar(percent: 4, resetsAt: now.addingTimeInterval(71 * 3600)),
            scoped: [ScopedLimit(name: "Fable",
                                 bar: LimitBar(percent: 1, resetsAt: now.addingTimeInterval(71 * 3600)))],
            extra: nil,
            days: days,
            models: models,
            stats: LocalStats(sessions: 44, messages: 5_984, streakDays: 5, peakHour: 15,
                              totalTokens: models.reduce(0) { $0 + $1.tokens }),
            error: nil)
    }
}
