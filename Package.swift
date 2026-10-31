// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "IgniteroLauncher",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    .package(url: "https://github.com/krisk/fuse-swift", from: "1.4.0"),
    .package(url: "https://github.com/danielsaidi/EmojiKit", from: "3.1.0"),
  ],
  targets: [
    .binaryTarget(name: "OcrusFFI", path: "Native/OcrusFFI.xcframework"),
    .target(
      name: "IgniteroCore",
      dependencies: [
        "OcrusFFI",
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
        .product(name: "Fuse", package: "fuse-swift"),
        .product(name: "EmojiKit", package: "EmojiKit"),
      ],
      resources: [
        .copy("Resources/emoji_keywords_ja.json")
      ],
      linkerSettings: [.linkedLibrary("iconv"), .linkedLibrary("resolv")]
    ),
    .executableTarget(
      name: "IgniteroLauncher",
      dependencies: ["IgniteroCore"]
    ),
    .testTarget(
      name: "IgniteroCoreTests",
      dependencies: [
        "IgniteroCore",
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
        .product(name: "Fuse", package: "fuse-swift"),
      ]
    ),
  ]
)
