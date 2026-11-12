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
            url: "https://github.com/open4id-community/ios-sdk/releases/download/v0.7.0/Open4IDSDK-0.7.0.xcframework.zip",
            checksum: "9b279110c65345ebbaddd7373c978551ce16caf041de7903b649f58a2f2658e2"
        )
    ]
)
