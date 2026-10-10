// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConcentrationSlop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ConcentrationSlop", targets: ["ConcentrationSlop"])],
    targets: [
        .executableTarget(name: "ConcentrationSlop"),
        .testTarget(name: "ConcentrationSlopTests", dependencies: ["ConcentrationSlop"], resources: [.copy("Fixtures")])
    ]
)
