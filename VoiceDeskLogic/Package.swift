// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceDeskLogic",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VoiceDeskLogic", targets: ["VoiceDeskLogic"])
    ],
    targets: [
        .target(name: "VoiceDeskLogic"),
        .testTarget(
            name: "VoiceDeskLogicTests",
            dependencies: ["VoiceDeskLogic"],
            resources: [
                .copy("Fixtures/voice-regression"),
                .copy("Fixtures/grok-voice-tape")
            ]
        )
    ]
)
