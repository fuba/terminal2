// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Terminal2",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Terminal2", targets: ["TerminalApp"])],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.1", traits: [])
    ],
    targets: [
        .target(name: "TerminalCore"),
        .executableTarget(name: "TerminalApp", dependencies: ["TerminalCore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .testTarget(name: "TerminalCoreTests", dependencies: ["TerminalCore"]),
        .testTarget(name: "TerminalAppTests", dependencies: ["TerminalApp"])
    ],
    swiftLanguageModes: [.v5]
)
