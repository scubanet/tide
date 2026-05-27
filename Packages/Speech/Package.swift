// swift-tools-version: 6.0
import PackageDescription

// Note: the module is named `TideSpeech` (not `Speech`) to avoid colliding
// with Apple's `Speech.framework`. Without the rename, `import Speech` from
// within our own module is treated by the compiler as importing ourselves
// (no-op), so the SF* types never become visible.
let package = Package(
  name: "TideSpeech",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TideSpeech", targets: ["TideSpeech"]),
  ],
  targets: [
    .target(name: "TideSpeech"),
    .testTarget(name: "TideSpeechTests", dependencies: ["TideSpeech"]),
  ]
)
