// swift-tools-version: 5.9

import PackageDescription
import Foundation

let vendorLib = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Vendor/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib/lib").path

let package = Package(
    name: "HearlyMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HearlyMac", targets: ["HearlyMac"])
    ],
    targets: [
        .systemLibrary(name: "SherpaOnnx"),
        .target(
            name: "HearlyAudioBridge",
            path: "Sources/HearlyAudioBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "HearlyMac",
            dependencies: ["HearlyAudioBridge", "SherpaOnnx"],
            path: "Sources/HearlyMac",
            exclude: ["Services/Accounts/AccountService.swift"],
            linkerSettings: [.unsafeFlags(["-L", vendorLib, "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", "-Xlinker", "-rpath", "-Xlinker", vendorLib])]
        )
    ]
)
