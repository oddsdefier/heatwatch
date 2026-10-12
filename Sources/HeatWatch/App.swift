import AppKit
import SwiftUI
import Charts

struct HistoryPoint: Identifiable, Encodable, Sendable {
    let date: Date
    let cpu: Double?
    let gpu: Double?
    var id: Date { date }
}

@MainActor
final class Monitor: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var history: [HistoryPoint] = []
    @Published var sharingError: String?
    @Published var copyLabel = "Copy data"
    private let worker = SamplingWorker()
    private let publisher = SnapshotPublisher()
    private var timer: Timer?
    private var inFlight = false
    private var generation = 0
    var onUpdate: ((Snapshot?) -> Void)?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 1
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke),
                                                         name: NSWorkspace.didWakeNotification, object: nil)
    }

    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        let expectedGeneration = generation
        Task { [weak self, worker] in
            let result = await worker.sample(generation: expectedGeneration)
            guard let self else { return }
            self.inFlight = false
            guard self.generation == expectedGeneration else { self.refresh(); return }
            self.snapshot = result
            self.history.append(HistoryPoint(date: result.date, cpu: result.cpuTemperature,
                                             gpu: result.gpuTemperature))
            self.history.removeAll { result.date.timeIntervalSince($0.date) > 600 }
            if self.history.count > 121 { self.history.removeFirst(self.history.count - 121) }
            self.onUpdate?(result)
            self.copyLabel = "Copy data"
            let payload = SharedReadings(snapshot: result, history: self.history)
            self.sharingError = await self.publisher.publish(payload)
        }
    }

    @objc private func woke() {
        generation += 1
        snapshot = nil
        history.removeAll()
        onUpdate?(nil)
        refresh()
    }

    func copyReadings() {
        guard let snapshot else { return }
        do {
            let payload = SharedReadings(snapshot: snapshot, history: history)
            let data = try payload.jsonData()
            NSPasteboard.general.clearContents()
            copyLabel = NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
                ? "Copied" : "Copy failed"
        } catch { copyLabel = "Copy failed" }
    }
}

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @StateObject private var actions = AppActions()

    private func temperature(_ value: Double?) -> String {
        value.map { String(format: "%.1f°C", $0) } ?? "Unavailable"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "thermometer.medium").foregroundStyle(.orange)
                Text("HeatWatch").font(.headline)
                Spacer()
                if let snapshot = monitor.snapshot {
                    Text(snapshot.thermalState).font(.caption.weight(.semibold))
                        .foregroundStyle(snapshot.thermalState == "Normal" ? .green : .orange)
                }
            }
            if let snapshot = monitor.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(temperature(snapshot.cpuTemperature)).font(.system(size: 38, weight: .medium, design: .rounded))
                                Text("CPU average · " + snapshot.chip).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(temperature(snapshot.cpuPeak)).font(.headline)
                                Text("Hottest CPU core").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Chart {
                            ForEach(monitor.history) { point in
                                if let cpu = point.cpu {
                                    LineMark(x: .value("Time", point.date), y: .value("Temperature", cpu))
                                        .foregroundStyle(by: .value("Sensor", "CPU"))
                                }
                                if let gpu = point.gpu {
                                    LineMark(x: .value("Time", point.date), y: .value("Temperature", gpu))
                                        .foregroundStyle(by: .value("Sensor", "GPU"))
                                }
                            }
                        }
                        .chartForegroundStyleScale(["CPU": Color.orange, "GPU": Color.blue])
                        .chartYScale(domain: 20...110)
                        .chartXAxis(.hidden)
                        .chartLegend(position: .bottom, alignment: .leading, spacing: 4)
                        .frame(height: 70)
                        .accessibilityLabel("CPU and GPU temperatures over the last ten minutes")

                        HStack(spacing: 8) {
                            metric("GPU average", temperature(snapshot.gpuTemperature))
                            metric("Battery", temperature(snapshot.batteryTemperature))
                            metric("Fan", snapshot.fanRPM.map { "\(Int($0.rounded())) RPM" } ?? "Unavailable")
                        }
                        if let notice = snapshot.notice {
                            Text(notice).font(.caption).foregroundStyle(.orange)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Likely heat sources", systemImage: "magnifyingglass").font(.subheadline.weight(.semibold))
                            Text(snapshot.explanation).font(.caption).fixedSize(horizontal: false, vertical: true)
                            Text("CPU activity suggests contributors; it does not prove causation.")
                                .font(.caption2).foregroundStyle(.secondary)
                            if let gpu = snapshot.gpuUsage {
                                Text("Graphics activity: \(Int(gpu.rounded()))% · no per-app GPU readings")
                                    .font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text("Per-app graphics activity unavailable.").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                        HStack {
                            Text("CPU contributors").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("Now / \(Int(snapshot.evidenceSeconds.rounded()))s avg")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if snapshot.sampleSeconds == 0 {
                            Text("Measuring current CPU use…").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.contributors.prefix(6)) { contributor in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(contributor.name).font(.caption.weight(.medium)).lineLimit(1)
                                        Text(contributor.processCount == 0 ? "Recently exited" : "\(contributor.processCount) processes")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(String(format: "%.1f%% / %.1f%%", contributor.cpu, contributor.averageCPU))
                                        .font(.caption.monospacedDigit())
                                    let instances = actions.instances(for: contributor)
                                    if !instances.isEmpty {
                                        Menu {
                                            Button("Show app") { actions.show(contributor) }
                                            Button("Hide app") { actions.hide(contributor) }
                                            Divider()
                                            if instances.count == 1 {
                                                Button("Quit app…") { actions.confirmQuit(contributor) }
                                            } else {
                                                ForEach(instances, id: \.processIdentifier) { instance in
                                                    Button("Quit instance \(instance.processIdentifier)…") {
                                                        actions.confirmQuit(contributor, onlyPID: instance.processIdentifier)
                                                    }
                                                }
                                                Button("Quit all \(instances.count) instances…") {
                                                    actions.confirmQuit(contributor)
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                        }
                                        .menuStyle(.borderlessButton)
                                        .frame(width: 24)
                                        .accessibilityLabel("Actions for \(contributor.name)")
                                        .help("Normal app actions. No force quit.")
                                    }
                                }
                            }
                        }
                        DisclosureGroup("Top processes") {
                            VStack(spacing: 5) {
                                ForEach(snapshot.processes.prefix(6)) { process in
                                    HStack {
                                        Text("\(process.name) · \(process.pid)").lineLimit(1)
                                        Spacer()
                                        Text(String(format: "%.1f%%", process.cpu)).monospacedDigit()
                                    }.font(.caption2)
                                }
                            }.padding(.top, 4)
                        }.font(.caption)
                        if let message = actions.message {
                            Text(message).font(.caption).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Quit actions request normal app shutdown. Save work first.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("100% CPU means one full core. Brief tasks can escape sampling.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("Internal chip readings, not case temperature. Apple sets heat pressure.")
                            .font(.caption2).foregroundStyle(.secondary)
                        if let error = monitor.sharingError {
                            Text(error).font(.caption2).foregroundStyle(.orange)
                        } else {
                            Text("Local agent sharing: read-only snapshot, no extra probes.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxHeight: 560)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let age = max(0, Int(timeline.date.timeIntervalSince(snapshot.date)))
                    Text(age > 15 ? "Readings stale · \(age)s old" : "Updated \(age)s ago · refresh every 5s")
                        .font(.caption2).foregroundStyle(age > 15 ? Color.orange : Color.secondary)
                }
            } else {
                ProgressView("Reading sensors…").padding(.vertical, 24)
            }
            Divider()
            HStack {
                Button(monitor.copyLabel) { monitor.copyReadings() }
                    .disabled(monitor.snapshot == nil)
                    .accessibilityLabel(monitor.copyLabel)
                    .help("Copies JSON readings and the recent temperature trend.")
                Spacer()
                Button("Activity Monitor") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
                .buttonStyle(.link)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.link)
            }.font(.caption)
        }
        .padding(16)
        .frame(width: 430, height: 690)
    }

    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let monitor = Monitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: "HeatWatch")
            button.imagePosition = .imageLeading
            button.title = " —°C"
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: Dashboard(monitor: monitor))
        monitor.onUpdate = { [weak self] snapshot in
            self?.statusItem.button?.title = snapshot?.cpuTemperature.map {
                " \(Int($0.rounded()))°C"
            } ?? " —°C"
            self?.statusItem.button?.toolTip = snapshot.map {
                "CPU average · \($0.chip) · \($0.thermalState)"
            } ?? "HeatWatch · reading sensors"
        }
        monitor.start()
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.togglePopover() }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
}

@main
struct HeatWatch {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            let sampler = Sampler()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let count = min(120, max(1, Int(option("--samples")) ?? 4))
            for index in 0..<count {
                if index > 0 { Thread.sleep(forTimeInterval: 5) }
                do {
                    let data = try encoder.encode(sampler.sample())
                    print(String(decoding: data, as: UTF8.self))
                    fflush(stdout)
                } catch {
                    fputs("Cannot encode diagnostic readings: \(error)\n", stderr)
                    exit(1)
                }
            }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    private static func option(_ name: String) -> String {
        guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return "" }
        return CommandLine.arguments[index + 1]
    }
}
