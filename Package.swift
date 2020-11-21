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
    .package(name: "MangerKit", url: "/Users/michael/swift/manger-kit", .branch("pkg")),
    .package(name: "FanboyKit", url: "/Users/michael/swift/fanboy-kit", .branch("pkg")),
    .package(name: "Ola", url: "/Users/michael/swift/ola", .branch("pkg")),
    .package(name: "Skull", url: "https://github.com/michaelnisi/skull", from: "11.0.0"),
    .package(name: "Nuke", url: "https://github.com/kean/nuke", from: "9.0.0")
  ],
  targets: [
    .target(
      name: "FeedKit",
      dependencies: ["MangerKit", "FanboyKit", "Ola", "Skull", "Nuke"],
      resources: [
        .copy("Resources")
      ]),
    .testTarget(
      name: "FeedKitTests",
      dependencies: ["FeedKit"],
      resources: [
        .copy("__Snapshots__"),
        .copy("Resources")
      ])
  ]
)
