# Open4ID iOS SDK — binary distributions

Prebuilt `Open4IDSDK.xcframework` artifacts for publishers who cannot or do
not want to build the SDK from source locally. Swift consumers normally use
the SPM tag instead (see the repository root `Package.swift`); this folder
serves the Objective-C / XCFramework consumption path.

| Version | Artifact | SHA-256 (see `SHA256SUMS`) |
|---------|----------|----------------------------|
| 0.3.3   | `Open4IDSDK-0.3.3.xcframework.zip` | `7537a1e3bcfa8235bf23d44a74b1b7b08f7b962d5cf9c943e4933d3ce18358f1` |

## What is inside

- `ios-arm64/` — device slice
- `ios-arm64_x86_64-simulator/` — simulator slice (x86_64 + arm64)
- `Headers/Open4IDSDK-Swift.h` — generated ObjC interface
- `Open4IDSDK.swiftmodule/` — module-stable `.swiftinterface` set

## How to verify and install

```bash
shasum -a 256 -c SHA256SUMS          # optional integrity check
unzip Open4IDSDK-0.3.3.xcframework.zip -d ~/open4id-ios-sdk
```

Then in Xcode: **General → Frameworks, Libraries, and Embedded Content →
Add… → Add Other → Add Files…** and pick
`Open4IDSDK-0.3.3.xcframework` with **Embed & Sign**.

## Updating the folder (release process)

Please read `USER_GUIDE.md` for usage.
