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
            url: "https://github.com/open4id-community/ios-sdk/releases/download/v1.0.2/Open4IDSDK-1.0.2.xcframework.zip",
            checksum: "bf9c2611c741539d7d259855107ff275910e89f1f03e64be5a8715c1d4966d63"
        )
    ]
)
