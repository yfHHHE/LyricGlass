// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LyricGlass",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LyricGlass", targets: ["LyricGlass"])],
    targets: [
        .target(name: "LyricsCore"),
        .target(name: "PlaybackKit", dependencies: ["LyricsCore"]),
        .target(name: "PetAudio", linkerSettings: [.linkedFramework("CoreAudio")]),
        .executableTarget(name: "LyricGlass", dependencies: ["LyricsCore", "PlaybackKit", "PetAudio"]),
        .executableTarget(name: "LyricsCoreChecks", dependencies: ["LyricsCore", "PlaybackKit"], path: "Tests/LyricsCoreTests")
    ]
)
