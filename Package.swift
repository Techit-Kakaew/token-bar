// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TokenBar",
            path: "Sources/TokenBar",
            resources: [.process("Resources")],
            swiftSettings: [.unsafeFlags(["-Onone"], .when(configuration: .debug))]
        ),
        .testTarget(
            name: "TokenBarTests",
            dependencies: ["TokenBar"],
            path: "Tests/TokenBarTests",
            exclude: ["Fixtures"]
        )
    ]
)
