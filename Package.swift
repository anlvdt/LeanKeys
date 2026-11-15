// swift-tools-version:5.9
// LeanKeys: Vikey's engine (vendor/vikey, untouched) behind a C shim, with a Swift TypingEngine on top.
import PackageDescription

let package = Package(
    name: "LeanKeys",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LeanKeysKit", targets: ["LeanKeysKit"]),
    ],
    targets: [
        // Engine/ has no include/. SwiftPM refuses a publicHeadersPath outside the target, and with an explicit
        // `sources` list it wants the public headers directory among the sources: platforms/ (mac.h only, no code)
        // serves. The shim reaches the engine headers through its own header search paths.
        .target(
            name: "VikeyEngine",
            path: "vendor/vikey/Engine",
            sources: ["Engine.cpp", "Vietnamese.cpp", "SmartSwitchKey.cpp", "Driver.cpp", "platforms"],
            publicHeadersPath: "platforms",
            cxxSettings: [.headerSearchPath("platforms"), .unsafeFlags(["-w"])]
        ),
        .target(
            name: "VikeyShim",
            dependencies: ["VikeyEngine"],
            path: "leankeys/VikeyShim",
            cxxSettings: [
                .headerSearchPath("../../vendor/vikey/Engine"),
                .headerSearchPath("../../vendor/vikey/Engine/platforms"),
            ]
        ),
        .target(
            name: "LeanKeysKit",
            dependencies: ["VikeyShim"],
            path: "leankeys/LeanKeysKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LeanKeysKitTests",
            dependencies: ["LeanKeysKit"],
            path: "leankeys/Tests/LeanKeysKitTests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
