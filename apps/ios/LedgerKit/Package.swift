// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LedgerKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LedgerKit", targets: ["LedgerKit"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.26.0"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift",
            from: "7.11.0"
        ),
    ],
    targets: [
        .target(
            name: "LedgerKit",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "LedgerKitTests",
            dependencies: ["LedgerKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
