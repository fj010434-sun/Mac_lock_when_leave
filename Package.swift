// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WatchSignal", platforms: [.macOS(.v14)], products: [.executable(name: "WatchSignal", targets: ["WatchSignalApp"])], targets: [
 .target(name: "WatchSignalCore"),
 .target(name: "WatchSignalPlatform", dependencies: ["WatchSignalCore"]),
 .executableTarget(name: "WatchSignalApp", dependencies: ["WatchSignalCore", "WatchSignalPlatform"]),
 .executableTarget(name: "DiagnosticsTests", dependencies: ["WatchSignalCore", "WatchSignalPlatform"], path: "Tests")
])
