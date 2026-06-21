// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LectureTranslatorNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LectureTranslatorNative", targets: ["LectureTranslatorNative"])
    ],
    targets: [
        .executableTarget(
            name: "LectureTranslatorNative",
            path: "Sources"
        )
    ]
)
