// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LspHighlight",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/swiftlang/sourcekit-lsp.git", branch: "release/6.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "LspHighlight",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "LSPBindings", package: "sourcekit-lsp"),
                .target(name: "ClangWrapper")
            ]
        ),
        .executableTarget(
            name: "XcodeLspStyle",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "ClangWrapper",
            cSettings: [
                .headerSearchPath("include-extra")
            ], linkerSettings: [
                .unsafeFlags([
                    "-lclang",
                    "-L/Library/Developer/CommandLineTools/usr/lib",
                    "-rpath", "/Library/Developer/CommandLineTools/usr/lib"
                ])
            ]
        )
    ]
)
