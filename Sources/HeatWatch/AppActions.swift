import AppKit
import Foundation

/// Only normal user-facing apps support actions. Never act on raw helper PIDs.
@MainActor
final class AppActions: ObservableObject {
    @Published private(set) var message: String?
    private var pending: [NSRunningApplication] = []
    private var checkTimer: Timer?
    private var requestedCount = 0
    private var notSentCount = 0
    private var deadline = Date.distantPast

    func instances(for contributor: Contributor) -> [NSRunningApplication] {
        // A shared display name alone cannot identify a safe target.
        guard contributor.applicationPaths.count == 1,
              let path = contributor.applicationPaths.first else { return [] }
        let apps = NSWorkspace.shared.runningApplications.filter(eligible)
        guard let owner = apps.first(where: { $0.bundleURL?.standardizedFileURL.path == path }),
              let identifier = owner.bundleIdentifier, !identifier.isEmpty else { return [] }
        return apps.filter {
            $0.bundleIdentifier == identifier && $0.bundleURL?.standardizedFileURL.path == path
        }.sorted { $0.processIdentifier < $1.processIdentifier }
    }

    func show(_ contributor: Contributor) {
        guard let app = instances(for: contributor).first else { return }
        app.activate(options: [])
    }

    func hide(_ contributor: Contributor) {
        for app in instances(for: contributor) { app.hide() }
    }

    func confirmQuit(_ contributor: Contributor, onlyPID: pid_t? = nil) {
        guard pending.isEmpty else {
            message = "A Quit request is pending. Complete or cancel the app's save prompt."
            return
        }
        let targets = instances(for: contributor).filter { onlyPID == nil || $0.processIdentifier == onlyPID }
        guard !targets.isEmpty else { message = "No eligible app instances remain."; return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = targets.count == 1 ? "Quit \(contributor.name)?" : "Quit all \(targets.count) instances of \(contributor.name)?"
        let pids = targets.map { String($0.processIdentifier) }.joined(separator: ", ")
        alert.informativeText = "Normal Quit only. Save your work first. Apps may show save prompts or refuse to quit.\n\nHeatWatch never forces an app to close. An app may not warn about unsaved work.\n\nInstances: \(pids)"
        // Cancel is the default. Opening this dialog never sends a Quit request.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Request Quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let live = targets.filter(eligible)
        guard !live.isEmpty else { message = "Those instances already exited."; return }
        let accepted = live.filter { $0.terminate() }
        notSentCount = live.count - accepted.count
        guard !accepted.isEmpty else {
            message = "\(notSentCount) Quit request(s) were not sent. HeatWatch will not force it."
            return
        }
        pending = accepted
        requestedCount = accepted.count
        deadline = Date().addingTimeInterval(20)
        message = "Quit sent to \(accepted.count) instance(s). \(notSentCount) request(s) not sent. Complete save prompts in the app."
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkCompletion() }
        }
    }

    private func eligible(_ app: NSRunningApplication) -> Bool {
        !app.isTerminated && app.activationPolicy == .regular
            && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && app.bundleIdentifier != nil && app.bundleURL != nil
    }

    private func checkCompletion() {
        pending.removeAll { $0.isTerminated }
        if pending.isEmpty {
            message = "\(requestedCount) requested instance(s) exited. \(notSentCount) request(s) not sent."
            checkTimer?.invalidate()
            checkTimer = nil
        } else if Date() >= deadline {
            let exited = requestedCount - pending.count
            message = "\(exited) exited; \(pending.count) remain open; \(notSentCount) request(s) not sent. Save or cancel in the app. No force quit."
            pending.removeAll()
            checkTimer?.invalidate()
            checkTimer = nil
        }
    }
}
