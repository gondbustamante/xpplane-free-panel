// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XPlaneKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "XPlaneKit", targets: ["XPlaneKit"])
    ],
    targets: [
        .target(name: "XPlaneKit"),
        .testTarget(name: "XPlaneKitTests", dependencies: ["XPlaneKit"])
    ]
)
