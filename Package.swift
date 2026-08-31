// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Glance",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Glance", targets: ["Glance"])
  ],
  targets: [
    .executableTarget(
      name: "Glance",
      path: "Sources/Glance",
      resources: [.process("Resources")],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
      name: "GlanceTests",
      dependencies: ["Glance"],
      path: "Tests/GlanceTests",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
  ]
)
