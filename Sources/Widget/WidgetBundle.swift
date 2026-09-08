import SwiftUI
import WidgetKit

/// The extension reads `status.json` and draws it. It never opens a socket and never
/// touches the Keychain — both are the container app's job, which is what keeps this
/// bundle signable with an ad-hoc identity and no App Group.
struct UsageEntry: TimelineEntry {
    var date: Date
    var payload: UsagePayload
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), payload: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let payload = StatusStore.read() ?? .preview
        completion(UsageEntry(date: Date(), payload: payload))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let payload = StatusStore.read() ?? .empty
        let now = Date()

        // The percentages only change when the container app rewrites the file, and it
        // reloads the timeline when it does. These intermediate entries exist so the reset
        // countdowns tick down on their own between refreshes.
        let entries = stride(from: 0, to: 30, by: 5).map { minutes in
            UsageEntry(date: now.addingTimeInterval(Double(minutes) * 60), payload: payload)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct ClaudeUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    // macOS renders desktop widgets into a monochrome vibrant material while an app is in
    // front — the "Atenuar widgets en el escritorio" setting — and Notification Center
    // always does. Hue is dropped there, so the layouts have to be told to spend alpha
    // instead of colour; without this they come out as a grid of blank white rectangles.
    @Environment(\.widgetRenderingMode) private var renderingMode
    var entry: UsageEntry

    private var palette: Palette {
        renderingMode == .vibrant ? .vibrant : .fullColor
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  SmallLayout(payload: entry.payload, now: entry.date)
            case .systemLarge:  LargeLayout(payload: entry.payload, now: entry.date)
            default:            MediumLayout(payload: entry.payload, now: entry.date)
            }
        }
        .environment(\.palette, palette)
        .containerBackground(palette.card, for: .widget)
        // Tapping the widget opens the menu-bar app, which is also what re-registers the
        // extension after an update.
        .widgetURL(URL(string: "claudeusage://open"))
    }
}

struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.diegopuerto.claudeusage.widget", provider: UsageProvider()) { entry in
            ClaudeUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Uso de Claude")
        .description("Sesión, límite semanal y consumo de tokens de tu plan Claude.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
    }
}
