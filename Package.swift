// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LazyPets",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "LazyPets",
            path: "Sources/LazyPets",
            resources: [
                // Pixel-art sprite sheets, loaded at runtime via Bundle.module.
                .process("Resources")
            ]
        )
    ]
)
