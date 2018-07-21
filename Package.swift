// swift-tools-version:4.0

import PackageDescription

let package = Package(
  name: "swift_stdlib_crawler",
  dependencies: [
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "1.7.1"),
  ],
  targets: [
    .target(
      name: "swift_stdlib_crawler",
      dependencies: ["SwiftSoup"]
    ),
  ]
)
