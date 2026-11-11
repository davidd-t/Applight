// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Applight",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "ApplightCore"),
        .executableTarget(name: "Applight", dependencies: ["ApplightCore"]),
        .testTarget(name: "ApplightCoreTests", dependencies: ["ApplightCore"]),
    ]
)
