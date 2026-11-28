// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "typist",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "typist", targets: ["typist"]),
    ],
    targets: [
        .target(
            name: "TypistCore",
            path: "Sources/TypistCore"
        ),
        .executableTarget(
            name: "typist",
            dependencies: ["TypistCore"],
            path: "Sources/typist"
        ),
        .testTarget(
            name: "TypistCoreTests",
            dependencies: ["TypistCore"],
            path: "Tests/TypistCoreTests"
        ),
    ]
)
