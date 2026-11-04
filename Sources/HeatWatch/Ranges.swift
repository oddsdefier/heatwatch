import SwiftUI

/// Typical ranges give context. They are not limits; macOS heat pressure is the only warning.
struct Band: Identifiable {
    enum Tone { case low, mid, high }
    let name: String
    let lower: Double
    let upper: Double
    let scenario: String
    let tone: Tone
    var id: String { name }

    var color: Color {
        switch tone {
        case .low: return .primary.opacity(0.12)
        case .mid: return .primary.opacity(0.26)
        case .high: return accent.opacity(0.55)
        }
    }
}

struct HeatScale {
    let minimum: Double
    let maximum: Double
    let unit: String
    let bands: [Band]
    let source: String

    /// Builds contiguous bands from upper bounds. The last band ends at the scale maximum.
    init(_ minimum: Double, _ maximum: Double, unit: String, source: String,
         _ specs: [(String, Double, String, Band.Tone)]) {
        self.minimum = minimum
        self.maximum = maximum
        self.unit = unit
        self.source = source
        var lower = minimum
        bands = specs.map { name, upper, scenario, tone in
            defer { lower = upper }
            return Band(name: name, lower: lower, upper: upper, scenario: scenario, tone: tone)
        }
    }

    func band(for value: Double) -> Band {
        bands.first { value < $0.upper } ?? bands[bands.count - 1]
    }

    func fraction(_ value: Double) -> Double {
        min(1, max(0, (value - minimum) / (maximum - minimum)))
    }

    func rangeText(_ band: Band) -> String {
        let format = { (value: Double) in "\(Int(value))\(unit)" }
        if band.id == bands.first?.id { return "below \(format(band.upper))" }
        if band.id == bands.last?.id { return "above \(format(band.lower))" }
        return "\(Int(band.lower))–\(format(band.upper))"
    }

    static let cpu = HeatScale(20, 105, unit: " °C",
                               source: "Rough ranges from common Apple silicon readings. Not Apple limits.", [
        ("OK", HeatStatus.warmThreshold, "Reading, light browsing, idle", .low),
        ("Warm", HeatStatus.hotThreshold, "Video calls, many tabs, builds", .mid),
        ("Hot", 105, "Games, exports, long compiles", .high)
    ])

    static let gpu = HeatScale(20, 100, unit: " °C",
                               source: "Rough ranges from common Apple silicon readings. Not Apple limits.", [
        ("Idle", 45, "Desktop, text, light browsing", .low),
        ("Busy", 70, "Video, animations, external displays", .mid),
        ("Heavy", 100, "Games, 3D, video export", .high)
    ])

    static let battery = HeatScale(15, 55, unit: " °C",
                                   source: "General lithium-ion guidance. Apple suggests room temperatures of 10–35 °C.", [
        ("Cool", 25, "Cool room, light use", .low),
        ("Typical", 40, "Normal use and charging", .mid),
        ("Warm", 55, "Heavy load, hot room, fast charging. Sustained heat ages the battery faster.", .high)
    ])

    static let gpuLoad = HeatScale(0, 100, unit: "%", source: "Rough examples.", [
        ("Light", 20, "Desktop, browsing, text", .low),
        ("Moderate", 60, "Video, animations, external displays", .mid),
        ("Heavy", 100, "Games, 3D, video export", .high)
    ])
}

/// Shaded bands with a marker at the current value.
struct RangeBar: View {
    let scale: HeatScale
    let value: Double?
    var labeled = false
    var thickness: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let gap: CGFloat = 1.5
            let usable = width - gap * CGFloat(scale.bands.count - 1)
            let span = scale.maximum - scale.minimum
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(scale.bands) { band in
                            Rectangle().fill(band.color)
                                .frame(width: usable * (band.upper - band.lower) / span)
                        }
                    }
                    .frame(height: thickness)
                    .clipShape(Capsule())
                    if let value {
                        Capsule()
                            .fill(Color.primary)
                            .overlay(Capsule().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
                            .frame(width: 3, height: thickness + 7)
                            .offset(x: scale.fraction(value) * (width - 3))
                    }
                }
                .frame(height: thickness + 7)
                if labeled {
                    HStack(spacing: gap) {
                        ForEach(scale.bands) { band in
                            Text(band.name)
                                .font(.system(size: 9))
                                .foregroundStyle(value.map { scale.band(for: $0).id == band.id } == true
                                                 ? Color.primary : Color.secondary)
                                .frame(width: usable * (band.upper - band.lower) / span)
                        }
                    }
                }
            }
        }
        .frame(height: thickness + 7 + (labeled ? 15 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(scale.band(for: $0).name) range" } ?? "Unavailable")
    }
}

/// The band name for a value. Only the high band uses the accent.
struct BandChip: View {
    let scale: HeatScale
    let value: Double

    var body: some View {
        let band = scale.band(for: value)
        Text(band.name)
            .font(.caption2.weight(.medium))
            .foregroundStyle(band.tone == .high ? accent : Color.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(band.tone == .high ? AnyShapeStyle(accent.opacity(0.15)) : AnyShapeStyle(.quaternary),
                        in: Capsule())
            .fixedSize()
    }
}
