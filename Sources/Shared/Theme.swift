import SwiftUI
import AppKit

/// Design tokens lifted from the Claude Design prototype.
///
/// The prototype ships a dark and a light palette with the same accents. A widget or a
/// popover inherits the system appearance rather than choosing one, so every surface
/// token here is an `NSColor` dynamic provider resolving to the prototype's own value for
/// whichever appearance is active. The accents are brand colours and stay fixed.
enum Theme {
    // MARK: Accents — identical in both prototype themes.

    /// Claude's orange. `#D97757`.
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
    /// `#D9A24A`, the prototype's ≥70% state.
    static let warn = Color(red: 0.851, green: 0.635, blue: 0.290)
    /// `#C4453C`, the prototype's ≥90% state.
    static let danger = Color(red: 0.769, green: 0.271, blue: 0.235)

    /// The prototype's three-stop severity ramp, applied to a 0–100 percentage.
    static func color(forPercent percent: Double) -> Color {
        if percent >= 90 { return danger }
        if percent >= 70 { return warn }
        return accent
    }

    static func statusLabel(forPercent percent: Double) -> String {
        if percent >= 90 { return "Al límite" }
        if percent >= 70 { return "Alto" }
        return "Normal"
    }

    // MARK: Surfaces — the prototype's `--card`, `--elev`, `--line`, `--track`.

    private static func dynamic(dark: (Double, Double, Double, Double),
                                light: (Double, Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }

    /// `#2E2D2B` dark / `rgba(255,255,255,0.92)` light.
    static let card = dynamic(dark: (0.180, 0.176, 0.169, 1), light: (1, 1, 1, 0.92))
    /// `#3A3937` dark / `#F0EEE6` light — the inset stat tiles.
    static let elevated = dynamic(dark: (0.227, 0.224, 0.216, 1), light: (0.941, 0.933, 0.902, 1))
    /// `rgba(255,255,255,0.08)` dark / `rgba(0,0,0,0.08)` light.
    static let line = dynamic(dark: (1, 1, 1, 0.08), light: (0, 0, 0, 0.08))
    /// `rgba(255,255,255,0.10)` dark / `rgba(0,0,0,0.08)` light — unfilled bar track.
    static let track = dynamic(dark: (1, 1, 1, 0.10), light: (0, 0, 0, 0.08))

    // MARK: Text — `--text` and `--muted`.

    static let text = dynamic(dark: (0.961, 0.957, 0.929, 1), light: (0.122, 0.118, 0.114, 1))
    static let muted = dynamic(dark: (0.612, 0.604, 0.580, 1), light: (0.431, 0.424, 0.400, 1))

    /// Model ramp. The prototype hand-picks three tints of the accent for three models;
    /// this extends the same ramp far enough to cover every model a week can touch, so a
    /// sixth model gets a colour instead of falling off the end.
    static let modelRamp: [Color] = [
        Color(red: 0.851, green: 0.467, blue: 0.341),  // #D97757
        Color(red: 0.910, green: 0.627, blue: 0.533),  // #E8A088
        Color(red: 0.949, green: 0.804, blue: 0.745),  // #F2CDBE
        Color(red: 0.706, green: 0.545, blue: 0.443),  // #B48B71
        Color(red: 0.545, green: 0.478, blue: 0.435),  // #8B7A6F
        Color(red: 0.416, green: 0.400, blue: 0.376),  // #6A6660
    ]

    static func modelColor(_ index: Int) -> Color { modelRamp[index % modelRamp.count] }
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// The prototype sets reset countdowns in SF Mono so the digits stop jittering.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Palette

/// The colours a layout actually draws with, resolved for the way the host renders it.
///
/// macOS dims desktop widgets into a monochrome vibrant material whenever an app is in
/// front, and WidgetKit reports that as `WidgetRenderingMode.vibrant`. Vibrancy keeps only
/// the alpha of what a view draws and throws the hue away, so every solid fill in the
/// full-colour palette — the tiles, the bars, the mark — collapses to the same flat white
/// and the widget reads as a row of blank rectangles. The vibrant palette re-expresses the
/// same hierarchy in alpha, which is the one channel that survives.
struct Palette {
    var isVibrant: Bool = false
    var accent: Color
    var warn: Color
    var danger: Color
    var card: Color
    var elevated: Color
    var line: Color
    var track: Color
    var text: Color
    var muted: Color
    var modelRamp: [Color]

    func color(forPercent percent: Double) -> Color {
        if percent >= 90 { return danger }
        if percent >= 70 { return warn }
        return accent
    }

    func modelColor(_ index: Int) -> Color { modelRamp[index % modelRamp.count] }

    /// The prototype's palette, used by the menu bar panel and by an undimmed widget.
    static let fullColor = Palette(
        accent: Theme.accent, warn: Theme.warn, danger: Theme.danger,
        card: Theme.card, elevated: Theme.elevated, line: Theme.line, track: Theme.track,
        text: Theme.text, muted: Theme.muted, modelRamp: Theme.modelRamp)

    /// Vibrancy renders white as fully present and darker content as more translucent, so
    /// every token here is white at the opacity that reproduces its full-colour weight.
    /// The severity ramp is nearly flat on purpose — hue cannot carry it, and the status
    /// label beside the dot already says "Normal", "Alto" or "Al límite" in words.
    static let vibrant = Palette(
        isVibrant: true,
        accent: .white.opacity(0.82),
        warn: .white.opacity(0.92),
        danger: .white,
        // The system draws its own material behind a dimmed widget; painting a card on top
        // of it is what turns the whole panel into one opaque slab.
        card: .clear,
        elevated: .white.opacity(0.16),
        line: .white.opacity(0.28),
        track: .white.opacity(0.22),
        text: .white,
        muted: .white.opacity(0.62),
        modelRamp: [1, 0.68, 0.46, 0.34, 0.26, 0.20].map { Color.white.opacity($0) })
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.fullColor
}

extension EnvironmentValues {
    /// Defaults to full colour, which is what a normal window always gets; only the widget
    /// root overrides it, and only when the system asks for vibrancy.
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Components

/// The prototype's rounded progress bar: a track with a rounded fill on top.
struct UsageBar: View {
    @Environment(\.palette) private var palette
    var fraction: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule()
                    .fill(color)
                    // A zero-width capsule renders nothing; the prototype still shows a
                    // dot at 1%, so keep a minimum stub once there is any usage at all.
                    .frame(width: fraction <= 0 ? 0 : max(height, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: height)
    }
}

/// One labelled row: caption on the left, percentage on the right, bar underneath.
struct LabeledBar: View {
    @Environment(\.palette) private var palette
    var title: String
    var percent: Double
    var caption: String?
    var titleSize: CGFloat = 13
    var barHeight: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.ui(titleSize)).foregroundStyle(palette.muted)
                Spacer(minLength: 8)
                Text("\(Int(percent.rounded()))% usado")
                    .font(.ui(titleSize, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.color(forPercent: percent))
            }
            UsageBar(fraction: percent / 100, color: palette.color(forPercent: percent), height: barHeight)
            if let caption {
                Text(caption).font(.mono(11)).foregroundStyle(palette.muted)
            }
        }
    }
}

/// The pulsing status dot from the prototype header. WidgetKit renders static snapshots,
/// so on the desktop this is a steady dot; the menu bar popover animates it.
struct StatusDot: View {
    var color: Color
    var size: CGFloat = 7
    var animated: Bool = false

    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(dim ? 0.35 : 1)
            .animation(animated ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : nil, value: dim)
            .onAppear { if animated { dim = true } }
    }
}

/// The rounded orange square that stands in for the Claude mark.
struct ClaudeMark: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Group {
            // Filled, the mark survives vibrancy as a plain white square, which reads as an
            // image that failed to load rather than as a logo. An outline stays a mark.
            if palette.isVibrant {
                shape.strokeBorder(palette.accent, lineWidth: max(1, size * 0.14))
            } else {
                shape.fill(palette.accent)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Header line shared by every layout: mark, plan name, status dot with its label.
struct UsageHeader: View {
    @Environment(\.palette) private var palette
    var title: String
    var worstPercent: Double
    var markSize: CGFloat = 16
    var titleSize: CGFloat = 14
    var showLabel: Bool = true
    var animated: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            ClaudeMark(size: markSize)
            // "Claude Max (5x)" does not fit beside the status label at medium width, and
            // wrapping it pushes the header two lines tall. Shrinking is the better trade.
            Text(title)
                .font(.ui(titleSize, .semibold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                StatusDot(color: palette.color(forPercent: worstPercent), animated: animated)
                if showLabel {
                    Text(Theme.statusLabel(forPercent: worstPercent))
                        .font(.ui(11, .semibold))
                        .foregroundStyle(palette.color(forPercent: worstPercent))
                }
            }
        }
    }
}

/// The stacked-bar sparkline: one column per day, one segment per model.
struct DaysChart: View {
    @Environment(\.palette) private var palette
    var days: [DayUsage]
    var modelOrder: [String]
    var showLabels: Bool
    var spacing: CGFloat = 5

    private var maxTotal: Int { max(1, days.map(\.total).max() ?? 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(days) { day in
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        VStack(spacing: 1) {
                            Spacer(minLength: 0)
                            ForEach(Array(modelOrder.enumerated()), id: \.offset) { index, model in
                                let tokens = day.byModel[model] ?? 0
                                if tokens > 0 {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(palette.modelColor(index))
                                        .frame(height: max(1.5, geo.size.height * Double(tokens) / Double(maxTotal)))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    if showLabels {
                        Text(day.label).font(.ui(9)).foregroundStyle(palette.muted)
                    }
                }
            }
        }
    }
}
