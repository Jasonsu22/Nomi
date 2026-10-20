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
    ],
    targets: [
        // Objective-C boundary for AVFoundation calls that raise NSException.
        .target(name: "NomiObjCSupport"),
        .executableTarget(
            name: "LectureNoteApp",
            dependencies: ["SwiftMath", "NomiObjCSupport"],
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
