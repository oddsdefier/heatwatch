import AppKit
import SwiftUI
import Charts

/// One accent marks what deserves attention. Everything else stays neutral.
let accent = Color.orange
let neutralFill = Color.primary.opacity(0.28)

func thermalColor(_ state: String) -> Color {
    switch state {
    case "Normal": return .secondary
    case "Warm", "High": return .orange
    case "Critical": return .red
    default: return .secondary
    }
}

struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @StateObject private var actions = AppActions()
    @StateObject private var listMode = ListMode()

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            if let snapshot = monitor.snapshot {
                ScrollView {
                    content(snapshot)
                        .padding(.vertical, 14)
                        .padding(.leading, 16)
                        // Gutter: the scroller sits here, never over content.
                        .padding(.trailing, 20)
                }
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Reading sensors")
            }
            Divider()
            footer.padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 360, height: 600)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "thermometer.medium").foregroundStyle(.orange)
            Text("HeatWatch").font(.headline)
            Spacer()
            if let snapshot = monitor.snapshot {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let age = max(0, Int(timeline.date.timeIntervalSince(snapshot.date)))
                    HStack(spacing: 4) {
                        if age > 15 { Text("\(age)s").font(.caption2.monospacedDigit()) }
                        Image(systemName: age > 15 ? "clock.badge.exclamationmark" : "clock")
                    }
                    .foregroundStyle(age > 15 ? Color.orange : Color.secondary)
                    .font(.caption)
                    .explainer(Explain.freshness(age: age))
                }
                HStack(spacing: 5) {
                    Circle().fill(thermalColor(snapshot.thermalState)).frame(width: 7, height: 7)
                    Text(snapshot.thermalState).font(.caption.weight(.medium))
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .explainer(Explain.state(snapshot.thermalState))
            }
        }
    }

    // MARK: Content

    private func content(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            hero(snapshot)
            if let notice = snapshot.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            trend
            tiles(snapshot)
            sensorMap(snapshot)
            contributors(snapshot)
            if let message = actions.message {
                Label(message, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hero(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heroNumbers(snapshot)
            RangeBar(scale: .cpu, value: snapshot.cpuTemperature, labeled: true, thickness: 6)
                .explainer(Explain.cpu(chip: snapshot.chip, value: snapshot.cpuTemperature))
        }
    }

    private func heroNumbers(_ snapshot: Snapshot) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                if let cpu = snapshot.cpuTemperature {
                    Text(String(format: "%.1f°", cpu))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("Unavailable").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text("CPU average").foregroundStyle(.secondary)
                    if let cpu = snapshot.cpuTemperature { BandChip(scale: .cpu, value: cpu) }
                }
                .font(.caption)
            }
            .explainer(Explain.cpu(chip: snapshot.chip, value: snapshot.cpuTemperature))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(snapshot.cpuPeak.map { String(format: "%.1f°", $0) } ?? "Unavailable")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(snapshot.cpuPeak == nil ? .secondary : .primary)
                Text("Hottest core").font(.caption).foregroundStyle(.secondary)
            }
            .explainer(Explain.peak)
        }
    }

    // MARK: Trend

    private var trend: some View {
        let values = monitor.history.flatMap { [$0.cpu, $0.gpu] }.compactMap { $0 }
        let low = values.min().map { (($0 - 4) / 5).rounded(.down) * 5 } ?? 30
        let high = values.max().map { (($0 + 4) / 5).rounded(.up) * 5 } ?? 80
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("10 min").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                legend("CPU", accent)
                legend("GPU", .gray)
            }
            .explainer(Explain.trend)
            Chart {
                ForEach(monitor.history) { point in
                    if let cpu = point.cpu {
                        AreaMark(x: .value("Time", point.date),
                                 yStart: .value("Base", low), yEnd: .value("CPU", cpu))
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", point.date), y: .value("Temperature", cpu),
                                 series: .value("Sensor", "CPU"))
                            .foregroundStyle(accent)
                            .interpolationMethod(.monotone)
                    }
                    if let gpu = point.gpu {
                        LineMark(x: .value("Time", point.date), y: .value("Temperature", gpu),
                                 series: .value("Sensor", "GPU"))
                            .foregroundStyle(Color.gray)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartYScale(domain: low...max(high, low + 10))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { if let degrees = value.as(Double.self) { Text("\(Int(degrees))°") } }
                        .font(.system(size: 9))
                }
            }
            .frame(height: 84)
            .accessibilityLabel("CPU and GPU temperatures over the last ten minutes")
        }
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Tiles

    private func tiles(_ snapshot: Snapshot) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Tile(symbol: "display", label: "GPU",
                     value: snapshot.gpuTemperature.map { String(format: "%.1f°", $0) },
                     scale: .gpu, reading: snapshot.gpuTemperature)
                    .explainer(Explain.gpu(snapshot.gpuTemperature))
                Tile(symbol: "gauge.medium", label: "GPU load",
                     value: snapshot.gpuUsage.map { "\(Int($0.rounded()))%" },
                     scale: .gpuLoad, reading: snapshot.gpuUsage)
                    .explainer(Explain.gpuLoad(snapshot.gpuUsage))
            }
            GridRow {
                Tile(symbol: snapshot.charging == true ? "battery.100percent.bolt" : "battery.75percent",
                     label: "Battery",
                     value: snapshot.batteryTemperature.map { String(format: "%.1f°", $0) },
                     scale: .battery, reading: snapshot.batteryTemperature)
                    .explainer(Explain.battery(charging: snapshot.charging, value: snapshot.batteryTemperature))
                Tile(symbol: "fan", label: "Fan",
                     value: snapshot.fanRPM.map { "\(Int($0.rounded())) rpm" },
                     scale: nil, reading: nil)
                    .explainer(Explain.fan)
            }
        }
    }

    // MARK: Cores

    /// One bar per sensor on a fixed 20–100 °C scale. The hottest sensor uses the accent.
    @ViewBuilder
    private func sensorMap(_ snapshot: Snapshot) -> some View {
        let cpu = snapshot.sensors.filter { $0.group == "CPU" }
        let groups: [(String, [SensorReading])] = [
            ("E", cpu.filter { $0.name.hasPrefix("Efficiency") }),
            ("P", cpu.filter { $0.name.hasPrefix("Performance") }),
            ("CPU", cpu.filter { !$0.name.hasPrefix("Efficiency") && !$0.name.hasPrefix("Performance") }),
            ("GPU", snapshot.sensors.filter { $0.group == "GPU" })
        ].filter { !$0.1.isEmpty }
        let hottest = snapshot.sensors.filter { $0.group != "Battery" }.max { $0.value < $1.value }
        if !groups.isEmpty, let hottest {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Sensors").font(.subheadline.weight(.semibold))
                    Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
                        .explainer(Explain.sensors(hottest: String(format: "%@, %.1f °C", hottest.name, hottest.value)))
                    Spacer()
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text(String(format: "%@ %.1f°", hottest.name, hottest.value))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                // Each group's width follows its sensor count, so all bars match.
                let total = Double(groups.reduce(0) { $0 + $1.1.count })
                let gaps = 14 * Double(groups.count - 1)
                GeometryReader { proxy in
                    HStack(alignment: .bottom, spacing: 14) {
                        ForEach(groups, id: \.0) { title, sensors in
                            coreGroup(title, sensors, hottest: hottest.key)
                                .frame(width: max(0, proxy.size.width - gaps) * Double(sensors.count) / total)
                        }
                    }
                }
                .frame(height: 64)
            }
        }
    }

    private func coreGroup(_ title: String, _ sensors: [SensorReading], hottest: String?) -> some View {
        let peak = sensors.map(\.value).max() ?? 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(sensors) { sensor in
                    let fraction = min(1, max(0.04, (sensor.value - 20) / 80))
                    // The track shows the full 20–100 °C scale behind each bar.
                    RoundedRectangle(cornerRadius: 1.5).fill(.quaternary.opacity(0.6))
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(sensor.key == hottest ? accent : neutralFill)
                                .frame(height: 46 * fraction)
                        }
                        .frame(maxWidth: .infinity)
                        .help(String(format: "%@ · %.1f°C", sensor.name, sensor.value))
                }
            }
            .frame(height: 46)
            HStack(spacing: 3) {
                Text(title).foregroundStyle(.secondary)
                Text(String(format: "%.0f°", peak)).monospacedDigit()
            }
            .font(.caption2)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%@ sensors, hottest %.0f degrees", title, peak))
    }

    // MARK: Contributors

    private func contributors(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Likely contributors").font(.subheadline.weight(.semibold))
                Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
                    .explainer(Explain.contributors(snapshot.explanation))
                Spacer()
                Picker("List", selection: $listMode.showProcesses) {
                    Text("Apps").tag(false)
                    Text("Processes").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            if snapshot.evidenceSeconds < 14.5 {
                ProgressView(value: min(snapshot.evidenceSeconds, 15), total: 15)
                    .progressViewStyle(.linear).controlSize(.mini)
                    .explainer(Explain.collecting)
            }
            if snapshot.sampleSeconds == 0 {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if listMode.showProcesses {
                processRows(snapshot)
            } else {
                appRows(snapshot)
            }
        }
    }

    private func appRows(_ snapshot: Snapshot) -> some View {
        let shown = Array(snapshot.contributors.prefix(6))
        let scale = max(100, shown.map { max($0.cpu, $0.averageCPU) }.max() ?? 0)
        return VStack(spacing: 1) {
            ForEach(shown) { contributor in
                let likely = contributor.averageCPU >= 20 && contributor.name != "kernel_task"
                UsageRow(iconPath: singlePath(contributor), name: contributor.name,
                         average: contributor.averageCPU / scale, now: contributor.cpu / scale,
                         value: contributor.averageCPU, highlighted: likely,
                         dimmed: contributor.processCount == 0) {
                    actionsMenu(contributor)
                }
                .help(String(format: "Now %.1f%% · %.0fs average %.1f%% · %@",
                             contributor.cpu, snapshot.evidenceSeconds, contributor.averageCPU,
                             contributor.processCount == 0 ? "recently exited"
                                                           : "\(contributor.processCount) processes"))
            }
        }
    }

    private func processRows(_ snapshot: Snapshot) -> some View {
        let shown = Array(snapshot.processes.prefix(6))
        let scale = max(100, shown.map(\.cpu).max() ?? 0)
        let paths = Dictionary(snapshot.contributors.compactMap { contributor in
            singlePath(contributor).map { (contributor.name, $0) }
        }, uniquingKeysWith: { first, _ in first })
        return VStack(spacing: 1) {
            ForEach(shown) { process in
                UsageRow(iconPath: paths[process.app], name: process.name,
                         average: process.cpu / scale, now: nil, value: process.cpu,
                         highlighted: false, dimmed: false) { EmptyView() }
                    .help("PID \(process.pid) · \(process.app) · CPU now")
            }
        }
    }

    private func singlePath(_ contributor: Contributor) -> String? {
        contributor.applicationPaths.count == 1 ? contributor.applicationPaths.first : nil
    }

    @ViewBuilder
    private func actionsMenu(_ contributor: Contributor) -> some View {
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
                    Button("Quit all \(instances.count) instances…") { actions.confirmQuit(contributor) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Actions for \(contributor.name)")
            .help("Normal app actions. No force quit. Save work first.")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button { monitor.copyReadings() } label: {
                Image(systemName: monitor.copyState.symbol)
                    .foregroundStyle(monitor.copyState == .failed ? Color.orange : Color.primary)
            }
            .disabled(monitor.snapshot == nil)
            .explainer(Explain.copy(monitor.copyState), edge: .top)
            .accessibilityLabel(monitor.copyState.help)
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            } label: {
                Image(systemName: "waveform.path.ecg")
            }
            .explainer(Explain.activity, edge: .top)
            Spacer()
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                .explainer(Explain.about, edge: .top)
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .explainer(Explain.quit, edge: .top)
        }
        .buttonStyle(.borderless)
        .font(.body)
    }
}

@MainActor
private final class ListMode: ObservableObject {
    @Published var showProcesses = false
}

/// One compact line: icon, name, short bar, value. Trailing actions appear on hover.
private struct UsageRow<Trailing: View>: View {
    let iconPath: String?
    let name: String
    let average: Double
    let now: Double?
    let value: Double
    let highlighted: Bool
    let dimmed: Bool
    @ViewBuilder let trailing: () -> Trailing
    @StateObject private var hover = HoverState()

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 16, height: 16)
            Text(name).font(.caption).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            UsageBar(average: average, now: now, tint: highlighted ? accent : neutralFill)
                .frame(width: 64)
            Text("\(Int(value.rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(highlighted ? accent : Color.secondary)
                .frame(width: 32, alignment: .trailing)
            // Reserve the slot so rows without actions keep the same columns.
            ZStack { Color.clear; trailing() }
                .frame(width: 16, height: 16)
                .opacity(hover.hovering ? 1 : 0)
                .allowsHitTesting(hover.hovering)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(hover.hovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hover.hovering = $0 }
        .opacity(dimmed ? 0.5 : 1)
        .padding(.horizontal, -6)
    }

    @ViewBuilder
    private var icon: some View {
        if let iconPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: iconPath)).resizable()
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

private struct Tile: View {
    let symbol: String
    let label: String
    let value: String?
    let scale: HeatScale?
    let reading: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol).frame(width: 16).foregroundStyle(.secondary)
                Text(label).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                if let scale, let reading { BandChip(scale: scale, value: reading) }
            }
            .font(.caption)
            Group {
                if let value {
                    Text(value).font(.title3.weight(.semibold).monospacedDigit())
                } else {
                    Text("Unavailable").font(.callout).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(height: 22, alignment: .leading)
            if let scale {
                RangeBar(scale: scale, value: reading)
            } else {
                Color.clear.frame(height: 12)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A thin track. Fill shows the average; an optional tick marks the current value.
private struct UsageBar: View {
    let average: Double?
    let now: Double?
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, average ?? 0)) * width)
                if let now {
                    Rectangle().fill(.primary.opacity(0.6))
                        .frame(width: 1.5, height: 7)
                        .offset(x: max(0, min(1, now)) * (width - 1.5))
                }
            }
        }
        .frame(height: 4)
    }
}
