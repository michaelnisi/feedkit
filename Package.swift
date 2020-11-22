// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "FeedKit",
  platforms: [
    .iOS(.v13), .macOS(.v10_15)
  ],
  products: [
    .library(
      name: "FeedKit",
      targets: ["FeedKit"]),
  ],
  dependencies: [
    .package(name: "MangerKit", url: "https://github.com/michaelnisi/manger-kit", from: "8.0.0"),
    .package(name: "FanboyKit", url: "https://github.com/michaelnisi/fanboy-kit", from: "9.0.0"),
    .package(name: "Ola", url: "https://github.com/michaelnisi/ola", from: "12.0.0"),
    .package(name: "Skull", url: "https://github.com/michaelnisi/skull", from: "11.0.0"),
    .package(name: "SnapshotTesting", url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.8.0")
  ],
  targets: [
    .target(
      name: "FeedKit",
      dependencies: ["MangerKit", "FanboyKit", "Ola", "Skull"],
      resources: [
        .process("Resources")
      ]),
    .testTarget(
      name: "FeedKitTests",
      dependencies: ["FeedKit", "SnapshotTesting"],
      resources: [
        .process("__Snapshots__"),
        .process("Resources")
      ])
  ]
)
