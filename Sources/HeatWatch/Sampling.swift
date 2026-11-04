import Foundation
import Darwin
import Hardware

struct ProcessCounter {
    let identity: String
    let pid: Int32
    let name: String
    let app: String
    let cpuNS: UInt64
    let bornUptime: Double?
    let applicationPath: String?
}

actor SamplingWorker {
    private let sampler = Sampler()
    private var generation = 0

    func sample(generation: Int) -> Snapshot {
        if generation != self.generation {
            sampler.reset()
            self.generation = generation
        }
        return sampler.sample()
    }
}

/// Names derived from an executable path. A live process keeps its path, so each resolves once.
private struct ProcessIdentity {
    let name: String
    let app: String
    let applicationPath: String?
}

private struct ProcessInterval {
    let seconds: Double
    let cpuSeconds: [String: Double]
}

/// Owns hardware handles and sampling order. Call only on one serial queue.
final class Sampler {
    private var connection: OpaquePointer?
    private var previous: [String: ProcessCounter] = [:]
    private var previousTime: Double?
    private var intervals: [ProcessInterval] = []
    private var identities: [String: ProcessIdentity] = [:]
    private var seenIdentities: [String: ProcessIdentity] = [:]
    private let chip: String
    private let catalog: [(String, String, String)]

    init() {
        chip = Self.cpuBrand()
        // Curated M4 sensor identities match Stats' M4 catalog.
        // Do not average guessed keys or lifetime maximum counters.
        if chip.contains("Apple M4") {
            let efficiency = ["Te05", "Te0S", "Te09", "Te0H"]
            let performance = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
            let graphics = ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
            catalog = efficiency.enumerated().map { ($0.element, "Efficiency core \($0.offset + 1)", "CPU") }
                + performance.enumerated().map { ($0.element, "Performance core \($0.offset + 1)", "CPU") }
                + graphics.enumerated().map { ($0.element, "Graphics sensor \($0.offset + 1)", "GPU") }
                + [("TB0T", "Battery", "Battery")]
        } else {
            catalog = [("TCMb", "CPU die", "CPU"), ("TB0T", "Battery", "Battery")]
        }
        connection = hw_open()
    }

    deinit { hw_close(connection) }

    func reset() {
        previous.removeAll()
        previousTime = nil
        intervals.removeAll()
        identities.removeAll()
        hw_close(connection)
        connection = hw_open()
    }

    func sample() -> Snapshot {
        let sensorDate = Date()
        if connection == nil { connection = hw_open() }
        let sensors = catalog.compactMap { key, name, group -> SensorReading? in
            let value = key.withCString { hw_sensor(connection, $0) }
            // Idle GPU sensors report placeholders such as 0.8. A running chip cannot read below 10 °C.
            guard value.isFinite, value >= 10, value < 150 else { return nil }
            return SensorReading(key: key, name: name, group: group, value: value)
        }
        let cpuValues = sensors.filter { $0.group == "CPU" }.map(\.value)
        let gpuValues = sensors.filter { $0.group == "GPU" }.map(\.value)
        let fan = "F0Ac".withCString { hw_sensor(connection, $0) }
        let gpu = hw_gpu_usage()
        let chargingValue = hw_charging()
        let collection = readProcesses()
        let counters = collection.counters
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTime.map { now - $0 } ?? 0
        // Wake, delayed sampling, and failures must not produce false averages.
        let validInterval = counters != nil && previousTime != nil && elapsed >= 0.5 && elapsed <= 15
        if !validInterval { intervals.removeAll() }
        var current: [String: ProcessCounter] = [:]
        var cpuSeconds: [String: Double] = [:]
        var processRows: [ProcessReading] = []
        if let counters {
            for counter in counters {
                current[counter.identity] = counter
                guard validInterval else { continue }
                let seconds: Double
                if let old = previous[counter.identity], counter.cpuNS >= old.cpuNS {
                    seconds = Double(counter.cpuNS - old.cpuNS) / 1_000_000_000
                } else if let birth = counter.bornUptime, let start = previousTime,
                          birth >= start, birth <= now {
                    seconds = Double(counter.cpuNS) / 1_000_000_000
                } else { continue }
                cpuSeconds[counter.app, default: 0] += seconds
                processRows.append(ProcessReading(pid: counter.pid, name: counter.name, app: counter.app,
                                                  cpu: seconds / elapsed * 100))
            }
            previousTime = now
        } else {
            previousTime = nil
        }
        previous = current
        if validInterval {
            intervals.append(ProcessInterval(seconds: elapsed, cpuSeconds: cpuSeconds))
            if intervals.count > 6 { intervals.removeFirst(intervals.count - 6) }
        }
        let evidenceSeconds = intervals.reduce(0) { $0 + $1.seconds }
        var appCPU: [String: Double] = [:]
        var appAverage: [String: Double] = [:]
        var appCounts: [String: Int] = [:]
        var appPaths: [String: Set<String>] = [:]
        for row in processRows { appCPU[row.app, default: 0] += row.cpu }
        for counter in current.values {
            appCounts[counter.app, default: 0] += 1
            if let path = counter.applicationPath { appPaths[counter.app, default: []].insert(path) }
        }
        if evidenceSeconds > 0 {
            for interval in intervals {
                for (app, seconds) in interval.cpuSeconds {
                    appAverage[app, default: 0] += seconds / evidenceSeconds * 100
                }
            }
        }
        let contributors = Set(appCPU.keys).union(appAverage.keys).map { app in
            Contributor(id: app, name: app, cpu: appCPU[app] ?? 0, averageCPU: appAverage[app] ?? 0,
                        processCount: appCounts[app] ?? 0, applicationPaths: Array(appPaths[app] ?? []).sorted())
        }.sorted {
            $0.averageCPU == $1.averageCPU ? $0.cpu > $1.cpu : $0.averageCPU > $1.averageCPU
        }
        let state = Self.thermalState()
        let notice: String?
        if cpuValues.isEmpty { notice = "CPU temperature unavailable. No guessed reading." }
        else if counters == nil { notice = "Process readings unavailable. Heat sources are unknown." }
        else if !collection.complete { notice = "Partial process readings. Some heat sources may be missing." }
        else if !chip.contains("Apple M4") { notice = "Limited sensor support on this chip." }
        else { notice = nil }
        return Snapshot(date: sensorDate, chip: chip, sensors: sensors,
                        cpuTemperature: SamplingRules.mean(cpuValues), cpuPeak: cpuValues.max(),
                        gpuTemperature: SamplingRules.mean(gpuValues),
                        batteryTemperature: sensors.first { $0.group == "Battery" }?.value,
                        fanRPM: fan.isFinite && fan >= 0 && fan <= 20000 ? fan : nil,
                        gpuUsage: gpu.isFinite ? gpu : nil,
                        charging: chargingValue < 0 ? nil : chargingValue != 0,
                        thermalState: state, contributors: Array(contributors.prefix(8)),
                        processes: Array(processRows.sorted { $0.cpu > $1.cpu }.prefix(8)),
                        observedProcesses: counters?.count ?? 0,
                        sampleSeconds: validInterval ? elapsed : 0,
                        evidenceSeconds: evidenceSeconds,
                        explanation: SamplingRules.explain(contributors, evidenceSeconds: evidenceSeconds,
                                                  gpuUsage: gpu.isFinite ? gpu : nil,
                                                  charging: chargingValue == 1,
                                                  processesAvailable: counters != nil,
                                                  completeCoverage: collection.complete), notice: notice)
    }

    private func readProcesses() -> (counters: [ProcessCounter]?, complete: Bool) {
        seenIdentities.removeAll(keepingCapacity: true)
        // Keep only processes seen in this sample. Exited processes leave the cache.
        defer { swap(&identities, &seenIdentities) }
        let native = nativeProcesses()
        let fallback = systemProcesses(excluding: Set((native ?? []).map(\.pid)))
        guard native != nil || fallback != nil else { return (nil, false) }
        return ((native ?? []) + (fallback ?? []), fallback != nil)
    }

    private func identity(_ key: String, pid: Int32) -> ProcessIdentity {
        if let known = identities[key] ?? seenIdentities[key] {
            seenIdentities[key] = known
            return known
        }
        var buffer = [CChar](repeating: 0, count: 4096)
        hw_process_path(pid, &buffer, UInt32(buffer.count))
        let path = String(cString: buffer)
        // String parts avoid the file system lookup that URL(fileURLWithPath:) makes.
        let parts = path.split(separator: "/")
        let name = pid == 0 ? "kernel_task" : parts.last.map(String.init) ?? "Process \(pid)"
        let app = parts.first { $0.hasSuffix(".app") }.map { String($0.dropLast(4)) } ?? name
        let resolved = ProcessIdentity(name: name, app: app, applicationPath: SamplingRules.applicationPath(for: path))
        // An empty path can be a transient failure. Retry it next sample.
        if !path.isEmpty || pid == 0 { seenIdentities[key] = resolved }
        return resolved
    }

    // ps exposes CPU time for system processes that deny proc_pid_rusage.
    // Request only numeric counters and start dates. Never request process titles.
    private func systemProcesses(excluding nativePIDs: Set<Int32>) -> [ProcessCounter]? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,time=,lstart="]
        task.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        defer { try? pipe.fileHandleForReading.close() }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) >= 0 else {
            kill(task.processIdentifier, SIGKILL)
            return nil
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var reachedEnd = false
        while ProcessInfo.processInfo.systemUptime < deadline {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                if data.count > 1_048_576 { break }
            } else if count == 0 {
                reachedEnd = true
                if !task.isRunning { break }
                Thread.sleep(forTimeInterval: 0.005)
            } else if errno == EAGAIN || errno == EINTR {
                var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                _ = poll(&event, 1, 20)
            } else { break }
        }
        guard reachedEnd, !task.isRunning, task.terminationStatus == 0 else {
            if task.isRunning { kill(task.processIdentifier, SIGKILL) }
            return nil
        }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 7, let pid = Int32(fields[0]), !nativePIDs.contains(pid),
                  let cpuNS = SamplingRules.cpuTime(String(fields[1])) else { return nil }
            let key = "ps:\(pid):\(fields[2...6].joined(separator: " "))"
            let known = identity(key, pid: pid)
            return ProcessCounter(identity: key, pid: pid, name: known.name,
                                  app: known.app, cpuNS: cpuNS, bornUptime: nil,
                                  applicationPath: known.applicationPath)
        }
    }

    private func nativeProcesses() -> [ProcessCounter]? {
        var pointer: UnsafeMutablePointer<HWProcess>?
        let count = hw_processes(&pointer)
        guard count >= 0, let pointer else { return nil }
        defer { hw_free_processes(pointer) }
        return (0..<Int(count)).map { index in
            let entry = pointer[index]
            let key = "\(entry.pid):\(entry.birth)"
            let known = identity(key, pid: entry.pid)
            return ProcessCounter(identity: key, pid: entry.pid,
                                  name: known.name, app: known.app, cpuNS: entry.cpu_ns,
                                  bornUptime: Double(entry.birth) / 1_000_000_000,
                                  applicationPath: known.applicationPath)
        }
    }

    private static func cpuBrand() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown chip" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "Unknown chip" }
        return String(cString: bytes)
    }

    private static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "High"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
