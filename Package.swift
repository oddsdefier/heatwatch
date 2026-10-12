// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HeatWatch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HeatWatch", targets: ["HeatWatch"])],
    targets: [
        .target(name: "Hardware", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "HeatWatch", dependencies: ["Hardware"])
    ]
)
