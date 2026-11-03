// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LyricGlass",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LyricGlass", targets: ["LyricGlass"])],
    targets: [
        .target(name: "LyricsCore"),
        .target(name: "PlaybackKit", dependencies: ["LyricsCore"]),
        .executableTarget(name: "LyricGlass", dependencies: ["LyricsCore", "PlaybackKit"]),
        .executableTarget(name: "LyricsCoreChecks", dependencies: ["LyricsCore", "PlaybackKit"], path: "Tests/LyricsCoreTests")
    ]
)
