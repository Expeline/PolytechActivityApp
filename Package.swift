// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolytechCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PolytechCore", targets: ["PolytechCore"])],
    targets: [
        .target(name: "PolytechCore", path: "Shared", exclude: ["LessonAttributes.swift"]),
        .testTarget(name: "PolytechCoreTests", dependencies: ["PolytechCore"],
                    path: "Tests/PolytechCoreTests", resources: [.copy("Fixtures")])
    ]
)
