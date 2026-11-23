// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniBookMaker",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "MiniBookMaker", targets: ["MiniBookMaker"])
    ],
    targets: [
        .executableTarget(
            name: "MiniBookMaker",
            path: "Sources/MiniBookMaker"
        )
    ]
)
