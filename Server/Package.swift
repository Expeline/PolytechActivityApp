// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolyServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.10.0"),
        // Shared models, schedule API client and ScheduleDiff — the same code the apps use.
        .package(name: "PolytechCore", path: ".."),
    ],
    targets: [
        .executableTarget(name: "PolyServer", dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "Fluent", package: "fluent"),
            .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            .product(name: "PolytechCore", package: "PolytechCore"),
        ]),
        .testTarget(name: "PolyServerTests", dependencies: [
            "PolyServer",
            .product(name: "XCTVapor", package: "vapor"),
        ], resources: [.copy("Fixtures")]),
    ]
)
