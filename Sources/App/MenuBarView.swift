import SwiftUI
import AppKit

/// Observable wrapper around `status.json` for the popover.
final class UsageModel: ObservableObject {
    @Published var payload: UsagePayload = StatusStore.read() ?? .empty { didSet { onChange?() } }

    /// Called on the main thread after `payload` changes, so the AppKit status-item button
    /// can redraw. SwiftUI views observe `@Published` directly and ignore this.
    var onChange: (() -> Void)?
    @Published var isRefreshing = false
    @Published var backgroundRefresh = LaunchAgent.isInstalled

    /// Redrawn every second so the reset countdowns tick while the popover is open.
    @Published var now = Date()
    private var ticker: Timer?

    func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
    }

    func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    func reload() {
        if let payload = StatusStore.read() { self.payload = payload }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let payload = Refresher.refresh()
            DispatchQueue.main.async {
                self.payload = payload
                self.isRefreshing = false
            }
        }
    }

    func setBackgroundRefresh(_ enabled: Bool) {
        if enabled {
            try? LaunchAgent.install()
        } else {
            LaunchAgent.uninstall()
        }
        backgroundRefresh = LaunchAgent.isInstalled
    }

    /// The number the menu bar shows and the status dot colours itself by.
    var worstPercent: Double {
        var values = [payload.session?.percent ?? 0, payload.weeklyAll?.percent ?? 0]
        values.append(contentsOf: payload.scoped.map(\.bar.percent))
        return values.max() ?? 0
    }
}

/// The prototype's 300pt menu-bar popover.
struct MenuBarPopover: View {
    @ObservedObject var model: UsageModel

    private var payload: UsagePayload { model.payload }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            UsageHeader(title: "Claude \(payload.plan)",
                        worstPercent: model.worstPercent,
                        markSize: 18,
                        animated: true)

            if let error = payload.error {
                ErrorNote(message: error)
            }

            if let session = payload.session {
                LabeledBar(title: "Sesión actual",
                           percent: session.percent,
                           caption: "Se reinicia en \(Fmt.countdown(to: session.resetsAt, now: model.now))")
            }

            if let weekly = payload.weeklyAll {
                LabeledBar(title: "Semanal · todos los modelos",
                           percent: weekly.percent,
                           caption: nil)
            }

            // Whichever model currently carries its own weekly budget. The API names it;
            // this does not hardcode Opus or Fable.
            ForEach(Array(payload.scoped.enumerated()), id: \.offset) { _, scoped in
                LabeledBar(title: "Semanal · \(scoped.name)",
                           percent: scoped.bar.percent,
                           caption: "Se reinicia en \(Fmt.countdown(to: scoped.bar.resetsAt, now: model.now))")
            }

            if let extra = payload.extra, extra.hasSpend {
                Divider().overlay(Theme.line)
                HStack {
                    Text("Uso extra").font(.ui(12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(String(format: "%.2f / %.0f %@", extra.usedCredits, extra.monthlyLimit, extra.currency))
                        .font(.ui(12, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                }
            }

            Divider().overlay(Theme.line)

            HStack(alignment: .firstTextBaseline) {
                Text("Últimos 7 días · Claude Code").font(.ui(12)).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Fmt.tokens(payload.stats.totalTokens)) tokens")
                    .font(.ui(12, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
            }

            DaysChart(days: payload.days,
                      modelOrder: payload.models.map(\.name),
                      showLabels: true,
                      spacing: 5)
                .frame(height: 52)

            Divider().overlay(Theme.line)

            // The prototype's footer: a link on the left, freshness and refresh on the
            // right. Both are plain buttons rather than `Link` and `Toggle`, which drag in
            // AppKit control chrome that does not match the design. The background-refresh
            // switch lives in the right-click menu instead.
            HStack(spacing: 10) {
                Button { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) } label: {
                    Text("Ajustes de uso").font(.ui(11)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(Fmt.ago(payload.fetchedAt, now: model.now))
                    .font(.ui(11)).foregroundStyle(Theme.muted)

                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.ui(11, .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .disabled(model.isRefreshing)
                .opacity(model.isRefreshing ? 0.4 : 1)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(Theme.card)
        .onAppear { model.startTicking(); model.reload() }
        .onDisappear { model.stopTicking() }
    }
}

private struct ErrorNote: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.ui(10))
                .foregroundStyle(Theme.warn)
            Text(message)
                .font(.ui(10))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.warn.opacity(0.12)))
    }
}
