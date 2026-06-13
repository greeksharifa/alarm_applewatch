// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AlarmAppleWatchCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "AlarmCore", targets: ["AlarmCore"])
    ],
    targets: [
        .target(
            name: "AlarmCore",
            path: "alarm_applewatch Watch App/AlarmCore"
        ),
        .testTarget(
            name: "AlarmCoreTests",
            dependencies: ["AlarmCore"],
            path: "Tests/AlarmCoreTests"
        )
    ]
)
