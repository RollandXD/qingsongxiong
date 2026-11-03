// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BearKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "BearFoundation", targets: ["BearFoundation"]),
        .library(name: "BearDesignSystem", targets: ["BearDesignSystem"]),
        .library(name: "BearPlatform", targets: ["BearPlatform"]),
        .library(name: "AIUsageDomain", targets: ["AIUsageDomain"]),
        .library(name: "AIUsageData", targets: ["AIUsageData"]),
        .library(name: "AIUsageFeature", targets: ["AIUsageFeature"]),
    ],
    targets: [
        .target(name: "BearFoundation"),
        .target(name: "BearDesignSystem", dependencies: ["BearFoundation"]),
        .target(name: "BearPlatform", dependencies: ["BearFoundation"]),
        .target(name: "AIUsageDomain", dependencies: ["BearFoundation"]),
        .target(name: "AIUsageData", dependencies: ["AIUsageDomain", "BearFoundation", "BearPlatform"]),
        .target(name: "AIUsageFeature", dependencies: ["AIUsageDomain", "BearDesignSystem"]),
        .testTarget(name: "BearFoundationTests", dependencies: ["BearFoundation"]),
        .testTarget(name: "BearPlatformTests", dependencies: ["BearPlatform", "BearFoundation"]),
        .testTarget(name: "AIUsageDomainTests", dependencies: ["AIUsageDomain"]),
        .testTarget(name: "AIUsageDataTests", dependencies: ["AIUsageData", "AIUsageDomain", "BearFoundation", "BearPlatform"]),
    ]
)
