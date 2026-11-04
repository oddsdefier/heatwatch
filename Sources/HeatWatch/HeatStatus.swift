/// Temperature bands provide context; only macOS heat pressure produces warnings.
enum HeatStatus: String, Sendable {
    case ok = "OK"
    case warm = "Warm"
    case hot = "Hot"
    case warning = "Warning"
    case critical = "Critical"
    case unavailable = "Unavailable"

    static let warmThreshold = 50.0
    static let hotThreshold = 80.0

    static func evaluate(cpuTemperature: Double?, thermalState: String) -> HeatStatus {
        switch thermalState {
        case "Critical": return .critical
        case "Warm", "High": return .warning
        case "Normal": break
        default: return .unavailable
        }
        guard let cpuTemperature, cpuTemperature.isFinite,
              cpuTemperature >= 10, cpuTemperature < 150 else { return .unavailable }
        if cpuTemperature < warmThreshold { return .ok }
        if cpuTemperature < hotThreshold { return .warm }
        return .hot
    }

    var guidance: String {
        switch self {
        case .ok: return "CPU temperature is in the light-use range. macOS reports normal heat pressure."
        case .warm: return "CPU temperature is elevated, which is common during active work. macOS reports normal heat pressure."
        case .hot: return "CPU temperature is high, which can happen under heavy load. macOS reports normal heat pressure. Check likely contributors if it stays hot."
        case .warning: return "macOS reports elevated heat pressure. Reduce heavy tasks and keep ventilation clear."
        case .critical: return "macOS reports critical heat pressure. Pause heavy tasks and let your Mac cool with ventilation clear."
        case .unavailable: return "CPU temperature or macOS heat pressure is unavailable. HeatWatch cannot assess the reading."
        }
    }

    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle"
        case .warm: return "thermometer.medium"
        case .hot: return "thermometer.high"
        case .warning, .critical: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle"
        }
    }
}
