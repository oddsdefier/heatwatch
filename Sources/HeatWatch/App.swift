import AppKit
import SwiftUI
import Charts

struct HistoryPoint: Identifiable, Encodable, Sendable {
    let date: Date
    let cpu: Double?
    let gpu: Double?
    var id: Date { date }
}

enum CopyState {
    case idle, copied, failed
    var symbol: String {
        switch self {
        case .idle: return "doc.on.doc"
        case .copied: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }
    var help: String {
        switch self {
        case .idle: return "Copy JSON readings and recent trend"
        case .copied: return "Copied"
        case .failed: return "Copy failed"
        }
    }
}

@MainActor
final class Monitor: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var history: [HistoryPoint] = []
    @Published var copyState = CopyState.idle
    private let worker = SamplingWorker()
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
            self.copyState = .idle
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
            copyState = NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
                ? .copied : .failed
        } catch { copyState = .failed }
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
            // Fixed-width digits stop the menu bar item from shifting.
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.title = " —°C"
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: Dashboard(monitor: monitor))
        monitor.onUpdate = { [weak self] snapshot in
            self?.updateStatusSymbol(snapshot?.thermalState)
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

    /// Symbol and tint follow Apple heat pressure only.
    private func updateStatusSymbol(_ state: String?) {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch state {
        case "Warm", "High", "Critical": symbol = "thermometer.high"
        default: symbol = "thermometer.medium"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "HeatWatch")
        switch state {
        case "High": button.contentTintColor = .systemOrange
        case "Critical": button.contentTintColor = .systemRed
        default: button.contentTintColor = nil
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            // An active app receives hover events and tooltips inside the panel.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
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
