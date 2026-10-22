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
    ],
    targets: [
        // Objective-C boundary for AVFoundation calls that raise NSException.
        .target(name: "NomiObjCSupport"),
        .executableTarget(
            name: "LectureNoteApp",
            dependencies: ["SwiftMath", "NomiObjCSupport", .product(name: "Sparkle", package: "Sparkle")],
            resources: [
                .copy("Fixtures"),
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "LectureNoteTests",
            dependencies: ["LectureNoteApp", "NomiObjCSupport"]
        ),
    ]
)
