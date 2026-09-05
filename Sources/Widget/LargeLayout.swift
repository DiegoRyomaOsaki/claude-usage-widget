import SwiftUI
import WidgetKit

/// `systemLarge`, 364×382 — the whole prototype: three limit tiles, the seven-day
/// sparkline, the per-model legend, and the footer counters.
struct LargeLayout: View {
    var payload: UsagePayload
    var now: Date

    /// Three tiles: session, weekly, and whichever model the API scopes separately.
    private var tiles: [(String, LimitBar)] {
        var result: [(String, LimitBar)] = []
        if let session = payload.session { result.append(("Sesión", session)) }
        if let weekly = payload.weeklyAll { result.append(("Semanal", weekly)) }
        if let scoped = payload.scoped.first { result.append((scoped.name, scoped.bar)) }
        return result
    }

    /// Only the models that actually ran; the legend is not a catalogue. Three rows is
    /// what fits once the footer is guaranteed its space.
    private var legend: [ModelUsage] { Array(payload.models.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UsageHeader(title: "Claude \(payload.plan)",
                        worstPercent: payload.worstPercent,
                        markSize: 18,
                        titleSize: 15)

            HStack(spacing: 8) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    LimitTile(title: tile.0, bar: tile.1, now: now)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                // Naming the source here keeps this total from reading as plan usage: the
                // tiles above are the whole account, this is Claude Code on this Mac.
                Text("Últimos 7 días · Claude Code").font(.ui(12)).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Text("\(Fmt.tokens(payload.stats.totalTokens)) tokens")
                    .font(.ui(12, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
            }

            // The chart is the one element that can give up height. Everything else has a
            // fixed size, so letting this flex is what keeps the footer labels on screen
            // when WidgetKit hands over less room than the prototype's canvas.
            DaysChart(days: payload.days,
                      modelOrder: payload.models.map(\.name),
                      showLabels: true,
                      spacing: 6)
                .frame(minHeight: 34, maxHeight: 60)
                .layoutPriority(-1)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(legend.enumerated()), id: \.offset) { index, model in
                    LegendRow(model: model,
                              color: Theme.modelColor(index),
                              share: payload.stats.totalTokens > 0
                                  ? Double(model.tokens) / Double(payload.stats.totalTokens)
                                  : 0)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                FooterStat(value: "\(payload.stats.sessions)", label: "Sesiones", divider: false)
                FooterStat(value: Fmt.count(payload.stats.messages), label: "Mensajes", divider: true)
                FooterStat(value: "\(payload.stats.streakDays)d", label: "Racha", divider: true)
                FooterStat(value: payload.stats.peakHourLabel, label: "Hora pico", divider: true)
            }
            .padding(.top, 7)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            // The footer is the first thing a clipped layout loses, and it is the row that
            // reads as broken when it goes. Pin it.
            .layoutPriority(1)
        }
    }
}

/// One of the three inset tiles across the top.
private struct LimitTile: View {
    var title: String
    var bar: LimitBar
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.ui(11, .medium)).foregroundStyle(Theme.muted).lineLimit(1)
            Text("\(Int(bar.percent.rounded()))%")
                .font(.ui(22, .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.color(forPercent: bar.percent))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            UsageBar(fraction: bar.fraction, color: Theme.color(forPercent: bar.percent), height: 4)
            Text(Fmt.countdown(to: bar.resetsAt, now: now))
                .font(.mono(10)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.elevated))
    }
}

/// One model in the legend: swatch, name, share bar, tokens, percentage.
private struct LegendRow: View {
    var model: ModelUsage
    var color: Color
    var share: Double

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(model.name)
                .font(.ui(11, .medium)).foregroundStyle(Theme.text)
                .frame(width: 64, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(color).frame(width: max(0, geo.size.width * share))
                }
            }
            .frame(height: 3)
            Text(Fmt.tokens(model.tokens))
                .font(.ui(11)).monospacedDigit().foregroundStyle(Theme.muted)
            Text(String(format: "%.1f%%", share * 100))
                .font(.ui(11, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

private struct FooterStat: View {
    var value: String
    var label: String
    var divider: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.ui(14, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.ui(10)).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            if divider { Rectangle().fill(Theme.line).frame(width: 1) }
        }
    }
}
