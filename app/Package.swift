// swift-tools-version:5.9
import PackageDescription

// The engine (ArchiCore) is plain Swift + Foundation and builds on macOS, Windows and Linux.
// The Mac app and the command-line tool use Apple frameworks (SwiftUI, AppKit, SceneKit, JavaScriptCore),
// so they are only part of the package on macOS.
var products: [Product] = [.library(name: "ArchiCore", targets: ["ArchiCore"])]
var targets: [Target] = [
    .target(name: "ArchiCore", path: "Sources/ArchiCore"),
    .testTarget(name: "ArchiCoreTests", dependencies: ["ArchiCore"], path: "Tests/ArchiCoreTests"),
]
#if os(macOS)
products += [
    .executable(name: "ArchiApp", targets: ["ArchiApp"]),
    .executable(name: "archi-cli", targets: ["archi-cli"]),
]
targets += [
    .executableTarget(name: "ArchiApp", dependencies: ["ArchiCore"], path: "Sources/ArchiApp"),
    .executableTarget(name: "archi-cli", dependencies: ["ArchiCore"], path: "Sources/archi-cli"),
]
#endif

let package = Package(
    name: "ArchiTool",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
