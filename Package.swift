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
            url: "https://github.com/open4id-community/ios-sdk/releases/download/v1.0.3/Open4IDSDK-1.0.3.xcframework.zip",
            checksum: "f4875f9e1a967b0a29d55e29d1398c993a12c09123052dbb5f00ecc64fc7eb7c"
        )
    ]
)
