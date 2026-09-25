// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ArchiTool",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArchiCore", targets: ["ArchiCore"]),
        .executable(name: "ArchiApp", targets: ["ArchiApp"]),
        .executable(name: "archi-cli", targets: ["archi-cli"]),
    ],
    targets: [
        .target(name: "ArchiCore", path: "Sources/ArchiCore"),
        .executableTarget(name: "ArchiApp", dependencies: ["ArchiCore"], path: "Sources/ArchiApp"),
        .executableTarget(name: "archi-cli", dependencies: ["ArchiCore"], path: "Sources/archi-cli"),
        .testTarget(name: "ArchiCoreTests", dependencies: ["ArchiCore"], path: "Tests/ArchiCoreTests"),
    ]
)
