import Foundation

struct SensorReading: Codable, Identifiable, Sendable {
    let key: String
    let name: String
    let group: String
    let value: Double
    var id: String { key }
}

struct Contributor: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let cpu: Double
    let averageCPU: Double
    let processCount: Int
    var applicationPaths: [String] = []

    // Paths identify UI actions only; exported data does not need them.
    private enum CodingKeys: String, CodingKey {
        case id, name, cpu, averageCPU, processCount
    }
}

struct ProcessReading: Codable, Identifiable, Sendable {
    let pid: Int32
    let name: String
    let app: String
    let cpu: Double
    var id: Int32 { pid }
}

struct Snapshot: Codable, Sendable {
    let date: Date
    let chip: String
    let sensors: [SensorReading]
    let cpuTemperature: Double?
    let cpuPeak: Double?
    let gpuTemperature: Double?
    let batteryTemperature: Double?
    let fanRPM: Double?
    let gpuUsage: Double?
    let charging: Bool?
    let thermalState: String
    let contributors: [Contributor]
    let processes: [ProcessReading]
    let observedProcesses: Int
    let sampleSeconds: Double
    let evidenceSeconds: Double
    let explanation: String
    let notice: String?
}

struct HistoryPoint: Identifiable, Encodable, Sendable {
    let date: Date
    let cpu: Double?
    let gpu: Double?
    var id: Date { date }
}
