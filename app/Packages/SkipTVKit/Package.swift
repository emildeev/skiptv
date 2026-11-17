// swift-tools-version:5.9

import PackageDescription

// Platform-independent logic of the SkipTV app: Plex API, detector client,
// skip policy, next-episode lookup, progress reporting and track selection.
// No UIKit/SwiftUI here, so `swift test` runs on macOS and Linux.
let package = Package(
    name: "SkipTVKit",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SkipTVKit", targets: ["SkipTVKit"]),
    ],
    targets: [
        .target(name: "SkipTVKit"),
        .testTarget(
            name: "SkipTVKitTests",
            dependencies: ["SkipTVKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
