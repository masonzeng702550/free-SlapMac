// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "SlapMac",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SlapMac",
            path: "Sources/SlapMac"
        )
    ]
)
