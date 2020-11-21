// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "FeedKit",
  platforms: [
    .iOS(.v13)
  ],
  products: [
    .library(
      name: "FeedKit",
      targets: ["FeedKit"]),
  ],
  dependencies: [
    .package(name: "MangerKit", url: "/Users/michael/swift/manger-kit", .branch("pkg")),
    .package(name: "FanboyKit", url: "/Users/michael/swift/fanboy-kit", .branch("pkg")),
    .package(name: "Ola", url: "/Users/michael/swift/ola", .branch("pkg")),
    .package(name: "Skull", url: "/Users/michael/swift/skull", .branch("master")),
    .package(name: "Nuke", url: "https://github.com/kean/nuke", from: "9.0.0"),
    .package(name: "SnapshotTesting", url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.8.0")
  ],
  targets: [
    .target(
      name: "FeedKit",
      dependencies: ["MangerKit", "FanboyKit", "Ola", "Skull", "Nuke"],
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
