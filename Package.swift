// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "NookStarter", platforms: [.macOS(.v14)], products: [
    .executable(name: "ModuleApp", targets: ["ModuleApp"]),
    .executable(name: "PluginCheck", targets: ["PluginCheck"]),
    .executable(name: "AgentCheck", targets: ["AgentCheck"])
], dependencies: [.package(path: "Vendor/NookPluginSDK"), .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"), .package(url: "https://github.com/apple/swift-system.git", from: "1.0.0")], targets: [
    .target(name: "ModuleCore", dependencies: [.product(name: "NookPluginSDK", package: "NookPluginSDK"), .product(name: "MCP", package: "swift-sdk"), .product(name: "SystemPackage", package: "swift-system")]),
    .executableTarget(name: "ModuleApp", dependencies: ["ModuleCore", .product(name: "NookPluginSDK", package: "NookPluginSDK")]),
    .executableTarget(name: "PluginCheck", dependencies: [.product(name: "NookPluginSDK", package: "NookPluginSDK")]),
    .executableTarget(name: "AgentCheck", dependencies: ["ModuleCore"]),
    .testTarget(name: "ModuleCoreTests", dependencies: ["ModuleCore"]),
    .testTarget(name: "AgentAppTests", dependencies: ["ModuleApp"])
], swiftLanguageModes: [.v5])
