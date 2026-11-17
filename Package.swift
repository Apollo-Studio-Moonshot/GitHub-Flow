// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitHubFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GitHubFlow", targets: ["GitHubFlow"])
    ],
    targets: [
        .executableTarget(
            name: "GitHubFlow",
            path: "Sources/GitHubFlow",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "GitHubFlowTests",
            dependencies: ["GitHubFlow"],
            path: "Tests/GitHubFlowTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
