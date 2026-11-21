// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LectureNoteApp",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "LectureNoteApp", targets: ["LectureNoteApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.3"),
        // Auto-update: daily checks, EdDSA-signed updates from GitHub Releases.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
        // Telling the teacher's voice from classmates' (Apache-2.0, Core ML). Diarization only: no TTS
        // or text normalization.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.4", traits: ["Diarizer"]),
    ],
    targets: [
        // Objective-C boundary for AVFoundation calls that raise NSException.
        .target(name: "NomiObjCSupport"),
        .executableTarget(
            name: "LectureNoteApp",
            dependencies: ["SwiftMath", "NomiObjCSupport", .product(name: "Sparkle", package: "Sparkle"), .product(name: "FluidAudio", package: "FluidAudio")],
            resources: [
                .copy("Fixtures"),
                // The answer page: markdown-it and KaTeX, MIT licensed (AnswerWeb/vendor/LICENSES.txt).
                .copy("AnswerWeb"),
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "LectureNoteTests",
            dependencies: ["LectureNoteApp", "NomiObjCSupport"]
        ),
    ]
)
