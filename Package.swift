// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Glance",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Glance", targets: ["Glance"])
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
  ],
  targets: [
    .executableTarget(
      name: "Glance",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle")
      ],
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
