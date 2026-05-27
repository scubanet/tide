// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Hotkeys",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "Hotkeys", targets: ["Hotkeys"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
  ],
  targets: [
    .target(name: "Hotkeys", dependencies: ["KeyboardShortcuts"]),
    .testTarget(name: "HotkeysTests", dependencies: ["Hotkeys"]),
  ]
)
