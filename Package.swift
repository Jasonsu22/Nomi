// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LectureNoteApp",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "LectureNoteApp", targets: ["LectureNoteApp"])
    ],
    targets: [
        .executableTarget(
            name: "LectureNoteApp",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "LectureNoteTests",
            dependencies: ["LectureNoteApp"]
        ),
    ]
)
