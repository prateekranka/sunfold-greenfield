// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SunfoldGreenfield",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SunfoldCore", targets: ["SunfoldCore"]),
    ],
    targets: [
        .target(
            name: "SunfoldCore",
            path: "Sources",
            sources: [
                "Domain",
                "Simulation",
                "Input/SelectionModel.swift",
                "Debug/DebugLog.swift",
            ]
        ),
        .testTarget(
            name: "SunfoldCoreTests",
            dependencies: ["SunfoldCore"],
            path: "Tests"
        ),
    ]
)
