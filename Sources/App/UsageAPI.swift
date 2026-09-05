import Foundation

/// The plan-limit half of the payload, read from Anthropic's OAuth endpoints with the
/// token Claude Code already holds.
///
/// `/api/oauth/usage` is the same data the `/usage` command and the claude.ai usage panel
/// show. Its `limits` array is the part worth reading: rather than a fixed set of keys it
/// returns one entry per active window, tagged `session`, `weekly_all`, or
/// `weekly_scoped` with the scoped model's display name attached. Parsing that array
/// instead of the older top-level `seven_day_opus` / `seven_day_sonnet` keys is why this
/// widget shows whichever model currently carries its own weekly budget without a code
/// change — Opus when the design was drawn, Fable now.
enum UsageAPI {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    enum Failure: LocalizedError {
        case unauthorized
        case http(Int)
        case malformed

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "El token de Claude Code caducó. Abre Claude Code una vez para renovarlo."
            case .http(let code):
                return "La API respondió HTTP \(code)."
            case .malformed:
                return "La API devolvió una respuesta que no pude leer."
            }
        }
    }

    struct Limits {
        var session: LimitBar?
        var weeklyAll: LimitBar?
        var scoped: [ScopedLimit]
        var extra: ExtraUsage?
    }

    // MARK: - Requests

    static func fetchLimits(token: String) throws -> Limits {
        let json = try getJSON(usageURL, token: token)
        return parse(json)
    }

    /// The human-facing plan name. Falls back to the Keychain's `rateLimitTier` when the
    /// profile call fails, so a network blip costs the subtitle and nothing else.
    static func fetchPlanName(token: String) -> String? {
        guard let json = try? getJSON(profileURL, token: token),
              let org = json["organization"] as? [String: Any] else { return nil }
        return planName(fromTier: org["rate_limit_tier"] as? String)
    }

    /// `default_claude_max_5x` → `Max (5x)`, `default_claude_pro` → `Pro`.
    static func planName(fromTier tier: String?) -> String? {
        guard let tier, !tier.isEmpty else { return nil }
        let stripped = tier
            .replacingOccurrences(of: "default_", with: "")
            .replacingOccurrences(of: "claude_", with: "")
        let parts = stripped.split(separator: "_").map(String.init)
        guard let family = parts.first else { return nil }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        if parts.count > 1 { return "\(name) (\(parts[1]))" }
        return name
    }

    private static func getJSON(_ url: URL, token: String) throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Without this beta header the endpoint rejects an OAuth bearer token.
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: Data?
        var status = 0
        var transportError: Error?
        let gate = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            payload = data
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            transportError = error
            gate.signal()
        }.resume()
        _ = gate.wait(timeout: .now() + 25)

        if let transportError { throw transportError }
        if status == 401 || status == 403 { throw Failure.unauthorized }
        guard status == 200 else { throw Failure.http(status) }
        guard let payload,
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw Failure.malformed
        }
        return json
    }

    // MARK: - Parsing

    static func parse(_ json: [String: Any]) -> Limits {
        var session: LimitBar?
        var weeklyAll: LimitBar?
        var scoped: [ScopedLimit] = []

        if let limits = json["limits"] as? [[String: Any]] {
            for entry in limits {
                guard let bar = bar(percent: entry["percent"], resetsAt: entry["resets_at"]) else { continue }
                switch entry["kind"] as? String {
                case "session":
                    session = bar
                case "weekly_all":
                    weeklyAll = bar
                case "weekly_scoped":
                    let scope = entry["scope"] as? [String: Any]
                    let model = scope?["model"] as? [String: Any]
                    let name = (model?["display_name"] as? String) ?? "Modelo"
                    scoped.append(ScopedLimit(name: name, bar: bar))
                default:
                    continue
                }
            }
        }

        // Older payloads, and any account the `limits` array does not cover, still carry
        // the two headline windows at the top level.
        if session == nil, let five = json["five_hour"] as? [String: Any] {
            session = bar(percent: five["utilization"], resetsAt: five["resets_at"])
        }
        if weeklyAll == nil, let seven = json["seven_day"] as? [String: Any] {
            weeklyAll = bar(percent: seven["utilization"], resetsAt: seven["resets_at"])
        }
        if scoped.isEmpty {
            for (key, label) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet")] {
                if let dict = json[key] as? [String: Any],
                   let b = bar(percent: dict["utilization"], resetsAt: dict["resets_at"]) {
                    scoped.append(ScopedLimit(name: label, bar: b))
                }
            }
        }

        var extra: ExtraUsage?
        if let dict = json["extra_usage"] as? [String: Any] {
            extra = ExtraUsage(isEnabled: (dict["is_enabled"] as? Bool) ?? false,
                               usedCredits: number(dict["used_credits"]) ?? 0,
                               monthlyLimit: number(dict["monthly_limit"]) ?? 0,
                               currency: (dict["currency"] as? String) ?? "USD")
        }

        return Limits(session: session, weeklyAll: weeklyAll, scoped: scoped, extra: extra)
    }

    private static func bar(percent: Any?, resetsAt: Any?) -> LimitBar? {
        guard let value = number(percent) else { return nil }
        return LimitBar(percent: value, resetsAt: date(resetsAt))
    }

    /// `percent` arrives as an Int and `utilization` as a Double, depending on the field.
    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    /// Reset timestamps carry fractional seconds; the plain formatter rejects those, so
    /// try both configurations.
    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
