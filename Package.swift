// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Qstats",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Qstats",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "MonitorTests",
            dependencies: ["Qstats"],
            path: "Tests/MonitorTests"
        )
    ]
)
