// swift-tools-version: 6.0
import PackageDescription

// Swift 5 language mode is used deliberately. The app is a main-actor-bound AppKit/SwiftUI
// application; Swift 6 strict concurrency adds no safety here but forces pervasive
// annotation of AppKit APIs that are already main-actor by contract.
let commonSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "QuickWins",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QuickWins", targets: ["QuickWins"]),
        .library(name: "QuickWinsCore", targets: ["QuickWinsCore"]),
    ],
    targets: [
        .target(
            name: "QuickWinsCore",
            swiftSettings: commonSettings
        ),
        .executableTarget(
            name: "QuickWins",
            dependencies: ["QuickWinsCore"],
            swiftSettings: commonSettings
        ),
        .testTarget(
            name: "QuickWinsCoreTests",
            dependencies: ["QuickWinsCore"],
            swiftSettings: commonSettings
        ),
    ]
)
