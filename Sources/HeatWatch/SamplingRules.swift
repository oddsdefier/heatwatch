import Foundation

/// Pure sampling calculations shared by the hardware sampler and deterministic tests.
enum SamplingRules {
    static func cpuTime(_ value: String) -> UInt64? {
        let dayParts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        var seconds: Double = 0
        if dayParts.count == 2 {
            guard let days = Double(dayParts[0]), days >= 0 else { return nil }
            seconds = days * 86400
        }
        guard let clock = dayParts.last else { return nil }
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        var factor: Double = 1
        for part in parts.reversed() {
            guard let number = Double(part), number >= 0 else { return nil }
            seconds += number * factor
            factor *= 60
        }
        guard seconds.isFinite, seconds < Double(UInt64.max) / 1_000_000_000 else { return nil }
        return UInt64(seconds * 1_000_000_000)
    }

    static func applicationPath(for executable: String) -> String? {
        guard executable.hasPrefix("/") else { return nil }
        let parts = executable.split(separator: "/")
        guard let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + parts[...index].joined(separator: "/")
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func explain(_ apps: [Contributor], evidenceSeconds: Double,
                        gpuUsage: Double?, charging: Bool, processesAvailable: Bool,
                        completeCoverage: Bool) -> String {
        guard processesAvailable else { return "Cannot identify likely sources without process readings." }
        guard evidenceSeconds >= 14.5 else { return "Collecting sustained CPU activity. Wait about 15 seconds." }
        var parts: [String] = []
        let active = apps.filter { $0.averageCPU >= 20 && $0.name != "kernel_task" }.prefix(2)
        if !active.isEmpty {
            parts.append("Likely CPU contributors: " + active.map {
                "\($0.name) (\(Int($0.averageCPU.rounded()))% average)"
            }.joined(separator: ", ") + ".")
        }
        if let gpuUsage, gpuUsage >= 30 {
            parts.append("Graphics activity is high. This reading cannot identify its app.")
        }
        if charging { parts.append("Battery charging may also add heat.") }
        if parts.isEmpty {
            parts.append(completeCoverage
                         ? "No sustained high CPU use in sampled processes. Brief tasks, graphics, airflow, or residual heat may contribute."
                         : "No sustained high CPU use in readable processes. Unread processes may add heat.")
        }
        if apps.contains(where: { $0.name == "kernel_task" && $0.averageCPU >= 20 }) {
            parts.append("kernel_task may reflect heat management, not the cause.")
        }
        return parts.joined(separator: " ")
    }
}
