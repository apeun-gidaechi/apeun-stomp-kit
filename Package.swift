// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ApeunStompKit",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(
            name: "ApeunStompKit",
            targets: ["ApeunStompKit"]
        ),
        .executable(name: "Test", targets: ["Test"])
    ],
    dependencies: [
        .package(url: "https://github.com/apeun-gidaechi/SocketRocket.git", exact: "1.0.0")
    ],
    targets: [
        .target(
            name: "ApeunStompKit",
            dependencies: [
                "SocketRocket"
            ],
            path: "./ApeunStompKit"
        ),
        .executableTarget(
            name: "Test",
            dependencies: ["ApeunStompKit"],
            path: "./Test"
        )
    ]
)
