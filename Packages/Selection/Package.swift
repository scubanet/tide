// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Selection",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "Selection", targets: ["Selection"]),
  ],
  targets: [
    .target(name: "Selection"),
    .testTarget(name: "SelectionTests", dependencies: ["Selection"]),
  ]
)
