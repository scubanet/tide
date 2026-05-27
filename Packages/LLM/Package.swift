// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "LLM",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "LLM", targets: ["LLM"]),
  ],
  dependencies: [
    .package(path: "../Core"),
  ],
  targets: [
    .target(name: "LLM", dependencies: ["Core"]),
    .testTarget(name: "LLMTests", dependencies: ["LLM"]),
  ]
)
