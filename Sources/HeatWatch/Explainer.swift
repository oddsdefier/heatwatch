import SwiftUI

/// A legend mark that matches what the panel draws.
enum LegendKey {
    case text(String)
    case swatch(Color)
    case dot(Color)
    case line(Color, dashed: Bool)
    case tick
}

/// A short hover explanation: title, one plain sentence or two, an optional legend, an optional live note.
struct Explanation {
    var symbol: String
    var title: String
    var body: String
    var legend: [(LegendKey, String)] = []
    var note: String?
    var scale: HeatScale?
    var value: Double?
}

enum Explain {
    static func state(_ current: String) -> Explanation {
        Explanation(symbol: "gauge.with.dots.needle.33percent", title: "Heat pressure",
                    body: "macOS reports this level. It is not a temperature.",
                    legend: [(.dot(.secondary), "Normal: no heat limits"),
                             (.dot(.orange), "Warm, High: macOS may slow the chip to cool it"),
                             (.dot(.red), "Critical: the Mac must cool down")],
                    note: "Now: \(current)")
    }

    static func freshness(age: Int) -> Explanation {
        age > 15
            ? Explanation(symbol: "clock.badge.exclamationmark", title: "Readings are stale",
                          body: "The last reading is \(age) seconds old. Readings usually refresh every 5 seconds.")
            : Explanation(symbol: "clock", title: "Live",
                          body: "Updated \(age) seconds ago. Readings refresh every 5 seconds.")
    }

    static func cpu(chip: String, value: Double?) -> Explanation {
        Explanation(symbol: "cpu", title: "CPU average",
                    body: "The mean of all CPU core sensors. This is the temperature inside the chip, "
                        + "not the case or the room.",
                    note: chip, scale: .cpu, value: value)
    }

    static let peak = Explanation(symbol: "arrow.up.to.line", title: "Hottest core",
                                  body: "The highest single CPU core now. One busy core can run hotter than the average.")

    static let trend = Explanation(symbol: "chart.xyaxis.line", title: "Last 10 minutes",
                                   body: "Temperature over time. The scale fits the data.",
                                   legend: [(.line(.orange, dashed: false), "CPU average"),
                                            (.line(.gray, dashed: true), "GPU average")])

    static func gpu(_ value: Double?) -> Explanation {
        Explanation(symbol: "display", title: "GPU temperature",
                    body: "The GPU is the graphics processor. It draws the screen, video, games, "
                        + "and browser effects. This value is the mean of its sensors.",
                    scale: .gpu, value: value)
    }

    static func gpuLoad(_ value: Double?) -> Explanation {
        Explanation(symbol: "gauge.medium", title: "GPU load",
                    body: "How busy the whole GPU is now, from 0 to 100%. "
                        + "macOS gives no split by app, so HeatWatch cannot name the app.",
                    scale: .gpuLoad, value: value)
    }

    static func battery(charging: Bool?, value: Double?) -> Explanation {
        Explanation(symbol: "battery.75percent", title: "Battery",
                    body: "Battery cell temperature. Charging and heavy use make it warmer.",
                    note: charging == true ? "Charging now" : nil, scale: .battery, value: value)
    }

    static let fan = Explanation(symbol: "fan", title: "Fan",
                                 body: "Fan speed in revolutions per minute (rpm). A faster fan moves more heat out. "
                                     + "macOS controls the fan. HeatWatch only reads it.")

    static func sensors(hottest: String) -> Explanation {
        Explanation(symbol: "chart.bar", title: "Sensors",
                    body: "One bar per sensor. A taller bar is hotter, on a scale from 20 to 100 °C.",
                    legend: [(.text("E"), "Efficiency cores: light work"),
                             (.text("P"), "Performance cores: heavy work"),
                             (.text("GPU"), "Graphics sensors"),
                             (.swatch(.orange), "Hottest sensor")],
                    note: "Hottest: \(hottest)")
    }

    static func contributors(_ explanation: String) -> Explanation {
        Explanation(symbol: "list.bullet", title: "Likely contributors",
                    body: "Apps that used the most CPU. They likely add heat. This does not prove the cause.",
                    legend: [(.swatch(.primary.opacity(0.28)), "Average use, last 30 s"),
                             (.tick, "Use now"),
                             (.swatch(.orange), "Average of 20% or more"),
                             (.text("100%"), "One full CPU core")],
                    note: explanation)
    }

    static let collecting = Explanation(symbol: "hourglass", title: "Collecting",
                                        body: "HeatWatch waits for about 15 seconds of activity "
                                            + "before it names likely contributors.")

    static func copy(_ state: CopyState) -> Explanation {
        switch state {
        case .idle: return Explanation(symbol: "doc.on.doc", title: "Copy data",
                                       body: "Copies the readings and the 10-minute trend as JSON. "
                                           + "Paste it into any chat assistant to ask about your Mac's heat.")
        case .copied: return Explanation(symbol: "checkmark", title: "Copied",
                                         body: "The readings are on the clipboard.")
        case .failed: return Explanation(symbol: "exclamationmark.triangle", title: "Copy failed",
                                         body: "The clipboard did not accept the data. Try again.")
        }
    }

    static let activity = Explanation(symbol: "waveform.path.ecg", title: "Activity Monitor",
                                      body: "Opens Apple's process viewer for full details.")

    static let about = Explanation(symbol: "questionmark.circle", title: "About these readings",
                                   body: "HeatWatch reads internal chip sensors every 5 seconds. "
                                       + "Very short tasks can escape sampling. HeatWatch never changes fan settings.")

    static let quit = Explanation(symbol: "power", title: "Quit HeatWatch",
                                  body: "Stops monitoring. Other apps keep running.")
}

// Command Line Tools lack the SwiftUI macro plugin that @State needs.
@MainActor
final class HoverState: ObservableObject {
    @Published var hovering = false
    @Published var shown = false
}

/// Shows a small popover after a short hover. Native tooltips are unreliable in menu-bar panels.
private struct Explainer: ViewModifier {
    let explanation: Explanation
    let edge: Edge
    @StateObject private var state = HoverState()

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { state.hovering = $0 }
            .task(id: state.hovering) {
                guard state.hovering else { state.shown = false; return }
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled && state.hovering { state.shown = true }
            }
            .popover(isPresented: $state.shown, arrowEdge: edge) {
                ExplanationCard(explanation: explanation)
            }
    }
}

private struct ExplanationCard: View {
    let explanation: Explanation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: explanation.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Text(explanation.title).font(.callout.weight(.semibold))
            }
            Text(explanation.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
            if let scale = explanation.scale {
                ScaleGuide(scale: scale, value: explanation.value)
            }
            if !explanation.legend.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(explanation.legend.indices, id: \.self) { index in
                        let (key, meaning) = explanation.legend[index]
                        HStack(spacing: 8) {
                            keyView(key).frame(width: 36, alignment: .center)
                            Text(meaning).font(.caption)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
            if let source = explanation.scale?.source {
                Label(source, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let note = explanation.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 252, alignment: .leading)
        .padding(14)
    }

    @ViewBuilder
    private func keyView(_ key: LegendKey) -> some View {
        switch key {
        case .text(let label):
            Text(label)
                .font(.caption2.monospaced().weight(.semibold))
                .fixedSize()
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        case .swatch(let color):
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 8)
        case .dot(let color):
            Circle().fill(color).frame(width: 7, height: 7)
        case .line(let color, let dashed):
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 18, y: 1))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 2] : []))
            .frame(width: 18, height: 2)
        case .tick:
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(width: 18, height: 4)
                Rectangle().fill(.primary.opacity(0.6)).frame(width: 1.5, height: 8).offset(x: 9)
            }
        }
    }
}

/// The band bar, then one row per scenario. The current band is highlighted.
private struct ScaleGuide: View {
    let scale: HeatScale
    let value: Double?

    var body: some View {
        let current = value.map(scale.band(for:))
        VStack(alignment: .leading, spacing: 8) {
            RangeBar(scale: scale, value: value, labeled: true, thickness: 6)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(scale.bands) { band in
                    let isCurrent = band.id == current?.id
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(band.color)
                            .frame(width: 10, height: 10)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(band.name).fontWeight(.semibold)
                                Text(scale.rangeText(band)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .font(.caption)
                            Text(band.scenario).font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        if isCurrent, let value {
                            Text(String(format: "Now %.0f%@", value, scale.unit))
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(isCurrent ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

extension View {
    func explainer(_ explanation: Explanation, edge: Edge = .bottom) -> some View {
        modifier(Explainer(explanation: explanation, edge: edge))
    }
}
