// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Ordo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Ordo",
            targets: ["OrdoApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OrdoApp"
        )
    ]
)
