enum SamplingChecks {
    static func run() {
        for (text, expected): (String, UInt64) in [
            ("0:00.00", 0), ("01:02.50", 62_500_000_000),
            ("125:00", 7_500_000_000_000), ("1:02:03", 3_723_000_000_000),
            ("2-01:02:03", 176_523_000_000_000)
        ] {
            precondition(SamplingRules.cpuTime(text) == expected, "CPU time: \(text)")
        }
        for text in ["", "nonsense", "1", "1::2", "1:", ":1", "-1:00", "1:-2", "1:2:3:4",
                     "NaN:00", "inf:00", "99999999999999999999999:00", "-1-00:00:00"] {
            precondition(SamplingRules.cpuTime(text) == nil, "Invalid CPU time: \(text)")
        }
        precondition(SamplingRules.mean([]) == nil, "Missing temperatures must not become zero")
        precondition(SamplingRules.mean([40, 50, 60]) == 50)

        precondition(SamplingRules.applicationPath(for: "/Applications/Editor.app/Contents/MacOS/Editor")
                     == "/Applications/Editor.app")
        precondition(SamplingRules.applicationPath(for: "/Applications/Browser.app/Contents/Helpers/Helper.app/MacOS/Helper")
                     == "/Applications/Browser.app", "Helpers belong to the outer app")
        for path in ["", "relative/Editor.app/Editor", "/usr/bin/swift"] {
            precondition(SamplingRules.applicationPath(for: path) == nil)
        }

        let active = Contributor(id: "Editor", name: "Editor", cpu: 100, averageCPU: 40, processCount: 2)
        let kernel = Contributor(id: "kernel_task", name: "kernel_task", cpu: 100, averageCPU: 80, processCount: 1)
        func explanation(_ apps: [Contributor] = [], seconds: Double = 30,
                         available: Bool = true, complete: Bool = true,
                         gpu: Double? = nil, charging: Bool = false) -> String {
            SamplingRules.explain(apps, evidenceSeconds: seconds, gpuUsage: gpu, charging: charging,
                                  processesAvailable: available, completeCoverage: complete)
        }
        precondition(explanation([active], seconds: 10).contains("Collecting"))
        precondition(!explanation([active], seconds: 10).contains("Editor"))
        precondition(explanation([active], available: false).contains("Cannot identify"))
        precondition(explanation([active]).contains("Likely CPU contributors: Editor"))
        precondition(explanation([active]).contains("40% average"))
        precondition(explanation([kernel]).contains("not the cause"))
        precondition(!explanation([kernel]).contains("Likely CPU contributors: kernel_task"))
        precondition(explanation(complete: false).contains("Unread processes may add heat"))
        precondition(explanation().contains("residual heat may contribute"))
        precondition(explanation(gpu: 30).contains("cannot identify its app"))
        precondition(explanation(charging: true).contains("charging may also add heat"))
        print("Passed CPU-time parsing, averages, app grouping, and contributor explanation checks.")
    }
}
