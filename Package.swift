// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portfox",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PortfoxKit", targets: ["PortfoxKit"]),
        .executable(name: "portfox-scan", targets: ["portfox-scan"])
    ],
    targets: [
        .target(
            name: "PortfoxKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "portfox-scan",
            dependencies: ["PortfoxKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PortfoxKitTests",
            dependencies: ["PortfoxKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
