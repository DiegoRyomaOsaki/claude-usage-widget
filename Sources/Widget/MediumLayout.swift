import SwiftUI
import WidgetKit

/// `systemMedium`, 364×170 — the prototype's ring next to the weekly rows.
struct MediumLayout: View {
    @Environment(\.palette) private var palette
    var payload: UsagePayload
    var now: Date

    private var session: LimitBar { payload.session ?? LimitBar(percent: 0, resetsAt: nil) }

    var body: some View {
        HStack(spacing: 18) {
            UsageRing(percent: session.percent, caption: "Sesión")
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 10) {
                UsageHeader(title: "Claude \(payload.plan)",
                            worstPercent: payload.worstPercent,
                            showLabel: true)

                if let weekly = payload.weeklyAll {
                    CompactBar(title: "Semanal · todos", percent: weekly.percent)
                }

                // The API decides which model has its own weekly budget; the widget just
                // prints the name it sends back.
                if let scoped = payload.scoped.first {
                    CompactBar(title: "Semanal · \(scoped.name)", percent: scoped.bar.percent)
                }

                HStack {
                    Text("Sesión \(Fmt.countdown(to: session.resetsAt, now: now))")
                    Spacer(minLength: 6)
                    Text("Semanal \(Fmt.countdown(to: payload.weeklyAll?.resetsAt, now: now))")
                }
                .font(.mono(10))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }
}

/// The prototype's 110pt progress ring with the percentage inside it.
struct UsageRing: View {
    @Environment(\.palette) private var palette
    var percent: Double
    var caption: String

    var body: some View {
        ZStack {
            Circle().stroke(palette.track, lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, max(0, percent / 100)))
                .stroke(palette.color(forPercent: percent),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(percent.rounded()))").font(.ui(28, .bold)).monospacedDigit()
                    Text("%").font(.ui(14, .semibold))
                }
                .foregroundStyle(palette.color(forPercent: percent))
                Text(caption).font(.ui(10, .medium)).foregroundStyle(palette.muted)
            }
        }
        .padding(4.5)
    }
}

/// A one-line bar row: caption, percentage, then the bar under both.
struct CompactBar: View {
    @Environment(\.palette) private var palette
    var title: String
    var percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.ui(12)).foregroundStyle(palette.muted).lineLimit(1)
                Spacer(minLength: 6)
                Text("\(Int(percent.rounded()))%")
                    .font(.ui(12, .semibold)).monospacedDigit().foregroundStyle(palette.text)
            }
            UsageBar(fraction: percent / 100, color: palette.color(forPercent: percent), height: 5)
        }
    }
}
