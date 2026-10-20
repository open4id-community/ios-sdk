// swift-tools-version:5.9
// SwiftPM distribution manifest for the Open4ID iOS SDK.
//
// This package ships the SDK as a prebuilt XCFramework binary target; the
// Swift sources are not published here. The zip lives in this repository
// (root, tracked on `main`) and its SHA-256 is recorded in SHA256SUMS.
//
// Consumers:
//     .package(url: "https://github.com/open4id-community/ios-sdk", from: "0.3.3")
// Objective-C consumers instead download the zip manually and embed it in
// Xcode (see README.md).
//
// NOTE: the URL points at the raw file on `main` rather than a release
// asset so the tag resolves as soon as it is pushed. The file at that path
// is immutable once published (a broken artifact means a new patch release,
// never a replacement upload).
import PackageDescription

let package = Package(
    name: "Open4IDSDK",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "Open4IDSDK", targets: ["Open4IDSDK"])
    ],
    targets: [
        .binaryTarget(
            name: "Open4IDSDK",
            url: "https://github.com/open4id-community/ios-sdk/raw/main/Open4IDSDK-0.3.3.xcframework.zip",
            checksum: "7537a1e3bcfa8235bf23d44a74b1b7b08f7b962d5cf9c943e4933d3ce18358f1"
        )
    ]
)
