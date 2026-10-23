# Open4ID iOS SDK — binary distributions

Prebuilt `Open4IDSDK.xcframework` artifacts for publishers who cannot or do
not want to build the SDK from source locally. This repo serves the
Objective-C / XCFramework consumption path. Swift consumers resolve the SDK
through SwiftPM instead:

- Public / Flutter-plugin consumers: this repository — tag `v<version>`;
  the root `Package.swift` is a `binaryTarget` manifest that fetches the
  zip below, so the Swift sources stay private.
- Internal consumers of the monorepo: the root `Package.swift` shim at the
  `v<version>` tag.

| Version | Artifact | SHA-256 (see `SHA256SUMS`) |
|---------|----------|----------------------------|
| 0.3.3   | `Open4IDSDK-0.3.3.xcframework.zip` | `7537a1e3bcfa8235bf23d44a74b1b7b08f7b962d5cf9c943e4933d3ce18358f1` |
| 0.4.0   | `Open4IDSDK-0.4.0.xcframework.zip` | `8a09740a9fe5b8c0707615d39b330b4bc42c2f1b5462b8046724f5896f0f2091` |

## What is inside

Both slices built with library evolution (`BUILD_LIBRARY_FOR_DISTRIBUTION`)
by the monorepo's `Scripts/build-xcframework.sh` at the tagged commit:

- `ios-arm64/` — device slice
- `ios-arm64_x86_64-simulator/` — simulator slice (x86_64 + arm64)
- `Headers/Open4IDSDK-Swift.h` — generated ObjC interface (includes the
  Phase 14 `Open4IDLoginDialogObjC` facade, the
  `Open4IDGoogleAuthorizationCodeProviding` provider protocol, the 0.4.0
  `signInWithFacebookWithCallbackUri:completion:` flow and the
  `setPortalOriginWithPortalOrigin:error:` overload)
- `Open4IDSDK.swiftmodule/` — module-stable `.swiftinterface` set

## How to verify and install

```bash
shasum -a 256 -c SHA256SUMS          # optional integrity check
unzip Open4IDSDK-0.4.0.xcframework.zip -d ~/open4id-ios-sdk
```

Then in Xcode: **General → Frameworks, Libraries, and Embedded Content →
Add… → Add Other → Add Files…** and pick
`~/open4id-ios-sdk/Open4IDSDK-0.4.0.xcframework` with **Embed & Sign**.

Please read `USER_GUIDE.md` for usage.
