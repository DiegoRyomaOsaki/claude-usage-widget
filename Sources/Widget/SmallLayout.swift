import SwiftUI
import WidgetKit

/// `systemSmall`, 170×170 — the prototype's 2×2 tile.
///
/// The session percentage is the headline: it is the window that actually stops work,
/// and the only one that moves on the scale of an afternoon.
struct SmallLayout: View {
    @Environment(\.palette) private var palette
    var payload: UsagePayload
    var now: Date

    private var session: LimitBar { payload.session ?? LimitBar(percent: 0, resetsAt: nil) }
    private var weekly: LimitBar { payload.weeklyAll ?? LimitBar(percent: 0, resetsAt: nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ClaudeMark(size: 16)
                Text("Claude").font(.ui(13, .semibold)).foregroundStyle(palette.text)
                Spacer(minLength: 4)
                StatusDot(color: palette.color(forPercent: payload.worstPercent))
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 0) {
                Text("Sesión").font(.ui(11, .medium)).foregroundStyle(palette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(session.percent.rounded()))")
                        .font(.ui(34, .bold))
                        .monospacedDigit()
                    Text("%").font(.ui(18, .semibold))
                }
                .foregroundStyle(palette.color(forPercent: session.percent))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                UsageBar(fraction: session.fraction,
                         color: palette.color(forPercent: session.percent),
                         height: 5)
                    .padding(.top, 6)

                Text(payload.isStale ? "sin datos" : "Reinicia en \(Fmt.countdown(to: session.resetsAt, now: now))")
                    .font(.mono(10))
                    .foregroundStyle(palette.muted)
                    .padding(.top, 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Semanal").font(.ui(11, .medium)).foregroundStyle(palette.muted)
                    Spacer()
                    Text("\(Int(weekly.percent.rounded()))%")
                        .font(.ui(11, .semibold)).monospacedDigit().foregroundStyle(palette.text)
                }
                UsageBar(fraction: weekly.fraction,
                         color: palette.color(forPercent: weekly.percent),
                         height: 5)
            }
        }
    }
}
