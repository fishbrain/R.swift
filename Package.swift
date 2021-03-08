// swift-tools-version:5.3
import PackageDescription

let package = Package(
  name: "rswift",
  platforms: [
    .macOS(.v10_15)
  ],
  products: [
    .executable(name: "rswift", targets: ["rswift"])
  ],
  dependencies: [
    .package(url: "https://github.com/kylef/Commander.git", from: "0.8.0"),
    .package(url: "https://github.com/tomlokhorst/XcodeEdit", from: "2.7.0"),
    .package(name: "SwiftPM", url: "https://github.com/apple/swift-package-manager", .branch("release/5.3"))
  ],
  targets: [
    .target(name: "rswift", dependencies: ["RswiftCore", "SwiftPM"]),
    .target(name: "RswiftCore", dependencies: ["Commander", "XcodeEdit", "SwiftPM"]),
    .testTarget(name: "RswiftCoreTests", dependencies: ["RswiftCore"]),
  ]
)
