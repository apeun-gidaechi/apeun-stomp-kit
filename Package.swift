// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ApeunStompKit",
    products: [
        .library(
            name: "ApeunStompKit",
            targets: ["ApeunStompKit"]
        )
    ],
    targets: [
        .target(
            name: "SocketRocket",
            path: "Sources/SocketRocket",
            exclude: ["Resources"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("Internal"),
                .headerSearchPath("Internal/Delegate"),
                .headerSearchPath("Internal/IOConsumer"),
                .headerSearchPath("Internal/Proxy"),
                .headerSearchPath("Internal/RunLoop"),
                .headerSearchPath("Internal/Security"),
                .headerSearchPath("Internal/Utilities")
            ],
            linkerSettings: [
                .linkedFramework("CFNetwork", .when(platforms: [.iOS, .tvOS])),
                .linkedFramework("Security"),
                .linkedFramework("CoreServices", .when(platforms: [.macOS])),
                .linkedLibrary("icucore")
            ]
        ),
        .target(
            name: "ApeunStompKit",
            dependencies: ["SocketRocket"],
            path: "Sources/ApeunStompKit"
        )
    ]
)
