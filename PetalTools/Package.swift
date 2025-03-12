// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PetalTools",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PetalTools",
            targets: ["PetalTools"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/google-gemini/generative-ai-swift", from: "0.5.6")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "PetalTools",
            dependencies: [
                .product(name: "GoogleGenerativeAI", package: "generative-ai-swift")
            ]
        ),
        .testTarget(
            name: "PetalToolsTests",
            dependencies: ["PetalTools"]
        )
    ]
)
