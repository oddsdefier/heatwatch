import Foundation

enum SharingChecks {
    static func run() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let contributor = Contributor(id: "Editor", name: "Editor", cpu: 125, averageCPU: 45,
                                      processCount: 3,
                                      applicationPaths: ["/Users/private-example/Applications/Editor.app"])
        func snapshot(temperature: Double?) -> Snapshot {
            Snapshot(date: date, chip: "Test chip", sensors: [], cpuTemperature: temperature,
                     cpuPeak: temperature, gpuTemperature: nil, batteryTemperature: nil,
                     fanRPM: nil, gpuUsage: nil, charging: nil, thermalState: "Normal",
                     contributors: [contributor], processes: [], observedProcesses: 3,
                     sampleSeconds: 5, evidenceSeconds: 30, explanation: "Likely contributors, not proven causes.",
                     notice: temperature == nil ? "CPU temperature unavailable." : nil)
        }
        let reading = snapshot(temperature: 40)
        let payload = SharedReadings(snapshot: reading, history: [HistoryPoint(date: date, cpu: 40, gpu: nil)])
        let data = try payload.jsonData()
        let text = String(decoding: data, as: UTF8.self)
        precondition(!text.contains("applicationPaths"), "App paths must not be exported")
        precondition(!text.contains("private-example"), "Private path components must not be exported")
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(root["schemaVersion"] as? Int == 1)
        let units = root["units"] as! [String: String]
        precondition(units["cpu"] == "percent_one_core")
        precondition(units["temperature"] == "celsius")
        precondition((root["history"] as! [[String: Any]]).count == 1)
        let exported = root["snapshot"] as! [String: Any]
        precondition(exported["date"] is String, "Dates must be ISO 8601 strings")
        precondition(exported["cpuTemperature"] as? Double == 40)
        let decoded = try JSONDecoder.iso8601.decode(Snapshot.self, from: JSONEncoder.iso8601.encode(reading))
        precondition(decoded.contributors.first?.applicationPaths == [], "UI-only paths are excluded on round trip")
        precondition(decoded.cpuTemperature == 40)

        let missing = try SharedReadings(snapshot: snapshot(temperature: nil), history: []).jsonData()
        let missingRoot = try JSONSerialization.jsonObject(with: missing) as! [String: Any]
        let missingSnapshot = missingRoot["snapshot"] as! [String: Any]
        precondition(missingSnapshot["cpuTemperature"] == nil, "Unavailable readings must not become zero")
        precondition((missingRoot["history"] as! [Any]).isEmpty)

        do {
            _ = try SharedReadings(snapshot: snapshot(temperature: .nan), history: []).jsonData()
            preconditionFailure("Nonfinite readings must fail encoding, not fabricate a value")
        } catch EncodingError.invalidValue { }
        print("Passed JSON schema, unavailable readings, round-trip, and export privacy checks.")
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
