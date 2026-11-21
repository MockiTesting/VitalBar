// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VitalBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VitalBar", targets: ["VitalBar"])
    ],
    targets: [
        .executableTarget(
            name: "VitalBar",
            path: "Sources/VitalBar",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        )
    ]
)
