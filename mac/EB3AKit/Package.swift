// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EB3AKit",
    platforms: [.macOS("26.0")],
    products: [.library(name: "EB3AKit", targets: ["EB3AKit"])],
    targets: [
        .target(name: "EB3AKit"),
        .testTarget(name: "EB3AKitTests", dependencies: ["EB3AKit"], resources: [.copy("Fixtures")]),
    ]
)
