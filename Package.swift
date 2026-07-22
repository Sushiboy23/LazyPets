// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LazyPets",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Consumed by the Xcode app target (LazyPets/LazyPets.xcodeproj) for
        // App Store / TestFlight builds.
        .library(name: "LazyPetsKit", targets: ["LazyPetsKit"])
    ],
    targets: [
        // All app code + sprites. Library (not executable) so the Xcode app
        // target can depend on it; dev builds use the thin executable below.
        .target(
            name: "LazyPetsKit",
            path: "Sources/LazyPetsKit",
            resources: [
                // Pixel-art sprite sheets, loaded at runtime via Bundle.module.
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "LazyPets",
            dependencies: ["LazyPetsKit"],
            path: "Sources/LazyPets"
        )
    ]
)
