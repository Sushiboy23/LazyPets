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
            path: "Sources/LazyPets"
        )
    ]
)
