// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ndi-webcam",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ndi-webcam",
            targets: ["ndi-webcam"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ndi-webcam",
            dependencies: [],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Foundation")
            ]
        ),
    ]
)