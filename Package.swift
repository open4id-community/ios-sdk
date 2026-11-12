// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Open4IDSDK",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "Open4IDSDK", targets: ["Open4IDSDK"])
    ],
    targets: [
        .binaryTarget(
            name: "Open4IDSDK",
            url: "https://github.com/open4id-community/ios-sdk/releases/download/v0.8.8/Open4IDSDK-0.8.8.xcframework.zip",
            checksum: "b31e60c99a933558c564a1c9663bdd68b691c8406a7a42f6d895bdf675ceffb4"
        )
    ]
)
