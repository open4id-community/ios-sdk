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
            url: "https://github.com/open4id-community/ios-sdk/releases/download/v0.6.0/Open4IDSDK-0.6.0.xcframework.zip",
            checksum: "4cc5fa555d1f412b37a653b4e7a1fcf603eeb91f67e2eaec330d703b5223910c"
        )
    ]
)
