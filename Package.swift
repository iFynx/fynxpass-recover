// swift-tools-version: 6.0
//
// fynxpass-recover: opens a FynxPass .fpx archive with printed Legacy shares, offline.
// No dependencies beyond Apple's CryptoKit, and no network code.

import PackageDescription

let package = Package(
    name: "fynxpass-recover",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "fynxpass-recover", targets: ["fynxpass-recover"])
    ],
    targets: [
        .target(name: "RecoverKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "fynxpass-recover",
            dependencies: ["RecoverKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RecoverKitTests",
            dependencies: ["RecoverKit", "fynxpass-recover"],
            resources: [.copy("Vectors")]
        )
    ]
)
