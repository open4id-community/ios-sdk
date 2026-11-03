# Open4ID iOS/macOS SDK — binary distributions

Prebuilt `Open4IDSDK.xcframework` artifacts for publishers who cannot or do
not want to build the SDK from source locally. This folder serves the
Objective-C / XCFramework consumption path. Swift consumers resolve the SDK
through SwiftPM instead:

- Public / Flutter-plugin consumers: `https://github.com/open4id-community/ios-sdk`
  — tag `v<version>`; the repo's root `Package.swift` is a `binaryTarget`
  manifest that fetches the zip below, so Swift sources stay private.
- Internal consumers of this monorepo: the root `Package.swift` shim at the
  `v<version>` tag.

| Version | Artifact | SHA-256 (see `SHA256SUMS`) |
|---------|----------|----------------------------|
| 0.3.3   | `Open4IDSDK-0.3.3.xcframework.zip` | `7537a1e3bcfa8235bf23d44a74b1b7b08f7b962d5cf9c943e4933d3ce18358f1` |
| 0.4.0   | `Open4IDSDK-0.4.0.xcframework.zip` | `8a09740a9fe5b8c0707615d39b330b4bc42c2f1b5462b8046724f5896f0f2091` |
| 0.5.0   | `Open4IDSDK-0.5.0.xcframework.zip` | `94e51e641657dcc61ad230d893c4d8deeffcf785862f04087f75e552b6d3930f` |

## What is inside

Built with library evolution (`BUILD_LIBRARY_FOR_DISTRIBUTION`) by
`../Scripts/build-xcframework.sh` at the tagged commit:

- `ios-arm64/` — iOS device slice
- `ios-arm64_x86_64-simulator/` — iOS simulator slice (x86_64 + arm64)
- `macos-arm64_x86_64/` — macOS slice (x86_64 + arm64); **0.5.0 and later**
- `Headers/Open4IDSDK-Swift.h` — generated ObjC interface per slice (includes
  the `Open4IDLoginDialogObjC` facade with its iOS `UIViewController` and
  macOS `NSViewController` overloads, the
  `Open4IDGoogleAuthorizationCodeProviding` provider protocol, and the
  payments surface)
- `Open4IDSDK.swiftmodule/` — module-stable `.swiftinterface` set

The `0.3.3` and `0.4.0` zips predate the macOS slice and contain only the iOS
slices; rebuild from a `0.5.0`+ tag (or from source) for macOS support.

## How to verify and install

```bash
shasum -a 256 -c SHA256SUMS          # optional integrity check
unzip Open4IDSDK-0.5.0.xcframework.zip -d ~/open4id-ios-sdk
```

Then in Xcode: **General → Frameworks, Libraries, and Embedded Content →
Add… → Add Other → Add Files…** and pick
`~/open4id-ios-sdk/Open4IDSDK-0.5.0.xcframework` with **Embed & Sign**.

For machine compatibility, prefer rebuilding from the same source tag
(`cd sdks/ios && Scripts/build-xcframework.sh`) — the zip is built on the
release host (Xcode 27, Swift 5.9+ toolchain) and is overwritten on each
release.

## Updating the folder (release process)

Full walkthrough: `docs/IOS_SDK_RELEASING.md` (build → zip → checksum →
tag → manual GitHub release upload). Quick version:

```bash
cd sdks/ios && Scripts/build-xcframework.sh
ditto build/Open4IDSDK.xcframework /tmp/Open4IDSDK-<version>.xcframework && \
  (cd /tmp && zip -qry Open4IDSDK-<version>.xcframework.zip
   Open4IDSDK-<version>.xcframework)
shasum -a 256 /tmp/Open4IDSDK-<version>.xcframework.zip >> SHA256SUMS
```

Then mirror the release to the GitHub SPM host (`open4id-community/ios-sdk`,
live since 0.3.3 — see `docs/IOS_SDK_RELEASING.md` §7 for the full record):

1. Push the zip to the GitHub repo root on `main` (same bytes, same checksum).
2. Update the root `Package.swift` `binaryTarget`: new `url` (raw/main path)
   and `checksum`.
3. Commit, tag `v<version>` (annotated, explicit `HEAD` target), push the tag.
4. Publish the GitHub Release with the zip attached (§6), then clean-room
   verify with `swift package resolve` against the GitHub URL.
