// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "RightCommandDictation",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "RightCommandDictation", targets: ["RightCommandDictation"])
    ],
    targets: [
        .executableTarget(
            name: "RightCommandDictation",
            path: "Sources"
        )
    ]
)
