// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "DevTools",
  platforms: [
    .iOS(.v17)
  ],
  products: [
    // A stupid-app project contains one library product per app/extension bundle.
    .library(name: "DevTools", targets: ["DevTools"]),
    .library(name: "DevToolsSafari", targets: ["DevToolsSafari"]),
  ],
  targets: [
    .target(name: "DevToolsCore", linkerSettings: [.linkedLibrary("sqlite3")]),
    .target(name: "DevTools", dependencies: ["DevToolsCore"]),
    .target(name: "DevToolsSafari", dependencies: ["DevToolsCore"]),
    .testTarget(name: "DevToolsCoreTests", dependencies: ["DevToolsCore"]),
  ]
)
