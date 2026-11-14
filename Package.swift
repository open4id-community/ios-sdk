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
            url: "https://github.com/open4id-community/ios-sdk/releases/download/v1.0.0/Open4IDSDK-1.0.0.xcframework.zip",
            checksum: "d020c129866ab6d977a4e1e819b2bbe30ab96d9048dfc04e6d3f94c2a71083f8"
        )
    ]
)
