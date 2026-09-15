// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NoMenu",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "NoMenu", targets: ["NoMenu"])
    ],
    targets: [
        .executableTarget(
            name: "NoMenu",
            path: "Sources/NoMenu",
            exclude: ["Resources"]
        )
    ]
)
