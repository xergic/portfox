// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PortFox",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PortFoxKit", targets: ["PortFoxKit"]),
        .executable(name: "portfox-scan", targets: ["portfox-scan"])
    ],
    targets: [
        .target(
            name: "PortFoxKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "portfox-scan",
            dependencies: ["PortFoxKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PortFoxKitTests",
            dependencies: ["PortFoxKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
