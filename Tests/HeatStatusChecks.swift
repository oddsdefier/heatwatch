enum HeatStatusChecks {
    static func run() {
        // Exact boundaries and values beyond the displayed scale.
        for (temperature, expected): (Double, HeatStatus) in [
            (10, .ok), (40, .ok), (49.9, .ok), (50, .warm),
            (79.9, .warm), (80, .hot), (105, .hot), (110, .hot), (149.9, .hot)
        ] {
            expect(temperature, "Normal", expected)
        }

        // Apple pressure overrides both temperature context and missing sensors.
        for temperature: Double? in [40, 65, 90, nil] {
            expect(temperature, "Warm", .warning)
            expect(temperature, "High", .warning)
            expect(temperature, "Critical", .critical)
        }

        for temperature: Double? in [nil, 0, 9.9, 150, .nan, .infinity, -.infinity] {
            expect(temperature, "Normal", .unavailable)
        }
        for pressure in ["Unknown", "", "Future state"] {
            expect(40, pressure, .unavailable)
        }
        for status: HeatStatus in [.ok, .warm, .hot, .warning, .critical, .unavailable] {
            precondition(!status.rawValue.isEmpty)
            precondition(!status.guidance.isEmpty)
            precondition(!status.symbol.isEmpty)
        }
        print("Passed 31 classification cases and all status text/symbol checks.")
    }

    private static func expect(_ temperature: Double?, _ pressure: String, _ expected: HeatStatus) {
        let actual = HeatStatus.evaluate(cpuTemperature: temperature, thermalState: pressure)
        precondition(actual == expected,
                     "Temperature \(String(describing: temperature)), pressure \(pressure): expected \(expected), got \(actual)")
    }
}
