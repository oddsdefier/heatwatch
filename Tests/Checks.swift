@main
struct Checks {
    static func main() throws {
        HeatStatusChecks.run()
        SamplingChecks.run()
        try SharingChecks.run()
        print("All deterministic checks passed.")
    }
}
