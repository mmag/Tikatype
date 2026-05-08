// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tikatype",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tikatype",
            path: "Sources/Tikatype",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
