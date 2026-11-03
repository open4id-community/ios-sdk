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
            url: "https://github.com/open4id-community/ios-sdk/releases/download/v0.5.0/Open4IDSDK-0.5.0.xcframework.zip",
            checksum: "94e51e641657dcc61ad230d893c4d8deeffcf785862f04087f75e552b6d3930f"
        )
    ]
)
