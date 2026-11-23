// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FluidVoice",
    platforms: [
        .macOS("15.0"),
    ],
    dependencies: [
        .package(path: "Vendor/WebRTCAudioProcessing"),
        .package(url: "https://github.com/mxcl/AppUpdater.git", from: "1.0.0"),
        // Pinned to jhgoodwin/FluidAudio main: altic-dev 386f7195 plus AsrModels `preprocessorComputeUnits`
        // (see SettingsStore.ParakeetPreprocessorComputeUnits and tools/patches/README.md) and speed ports from
        // FluidInference: parallel long-form chunks, CTC vocabulary preflight, zeroed CTC audio padding
        // (FluidAudio Documentation/ASR/SpeedPatches.md). Revert to altic-dev once merged there.
        // Keep the Xcode project's FluidAudio package reference on the same URL and revision.
        .package(url: "https://github.com/jhgoodwin/FluidAudio.git", revision: "9bdceb7ebfa16b2aa994cd9adfff01303ca597f4"),
        .package(url: "https://github.com/mxcl/PromiseKit", from: "6.0.0"),
        .package(url: "https://github.com/altic-dev/DynamicNotchKit.git", revision: "50dc8565469cc80bbbe3c0d5dd902585a2d67986"),
        .package(url: "https://github.com/altic-dev/transcribe-cpp-swift.git", exact: "0.1.2"),
        .package(url: "https://github.com/zepdb/zeppelin-embed.git", exact: "0.4.1"),
    ],
    targets: [
        .target(
            name: "CoreAudioCaptureSupport",
            path: "Sources/CoreAudioCaptureSupport",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
            ]
        ),
        .executableTarget(
            name: "FluidVoice",
            dependencies: [
                "AppUpdater",
                "CoreAudioCaptureSupport",
                "FluidAudio",
                "PromiseKit",
                "DynamicNotchKit",
                .product(name: "FluidAEC3Bridge", package: "WebRTCAudioProcessing"),
                .product(name: "TranscribeCpp", package: "transcribe-cpp-swift"),
                .product(name: "ZeppelinEmbed", package: "zeppelin-embed"),
            ],
            resources: [
                .copy("Resources/speech-model-check.pcm"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
