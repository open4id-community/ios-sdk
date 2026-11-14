# Open4ID iOS/macOS SDK — binary distributions

Prebuilt `Open4IDSDK.xcframework` artifacts for publishers who cannot or do
not want to build the SDK from source locally. This repo serves the
Objective-C / XCFramework consumption path. Swift consumers resolve the SDK
through SwiftPM instead:

- Public / Flutter-plugin consumers: this repository — tag `v<version>`;
  the root `Package.swift` is a `binaryTarget` manifest that fetches the
  zip attached to the GitHub Release, so the Swift sources stay private.
- Internal consumers of the monorepo: the root `Package.swift` shim at the
  `v<version>` tag.

| Version | Artifact | SHA-256 (see `SHA256SUMS`) |
|---------|----------|----------------------------|
| 0.3.3   | `Open4IDSDK-0.3.3.xcframework.zip` | `7537a1e3bcfa8235bf23d44a74b1b7b08f7b962d5cf9c943e4933d3ce18358f1` |
| 0.4.0   | `Open4IDSDK-0.4.0.xcframework.zip` | `8a09740a9fe5b8c0707615d39b330b4bc42c2f1b5462b8046724f5896f0f2091` |
| 0.5.0   | `Open4IDSDK-0.5.0.xcframework.zip` | `94e51e641657dcc61ad230d893c4d8deeffcf785862f04087f75e552b6d3930f` |
| 0.6.0   | `Open4IDSDK-0.6.0.xcframework.zip` | `4cc5fa555d1f412b37a653b4e7a1fcf603eeb91f67e2eaec330d703b5223910c` |
| 0.7.0   | `Open4IDSDK-0.7.0.xcframework.zip` | `9b279110c65345ebbaddd7373c978551ce16caf041de7903b649f58a2f2658e2` |
| 0.8.8   | `Open4IDSDK-0.8.8.xcframework.zip` | `b31e60c99a933558c564a1c9663bdd68b691c8406a7a42f6d895bdf675ceffb4` |
| 1.0.0   | `Open4IDSDK-1.0.0.xcframework.zip` | `d020c129866ab6d977a4e1e819b2bbe30ab96d9048dfc04e6d3f94c2a71083f8` |

## What is inside

Built with library evolution (`BUILD_LIBRARY_FOR_DISTRIBUTION`) by the
monorepo's `Scripts/build-xcframework.sh` at the tagged commit:

- `ios-arm64/` — iOS device slice
- `ios-arm64_x86_64-simulator/` — iOS simulator slice (x86_64 + arm64)
- `macos-arm64_x86_64/` — macOS slice (x86_64 + arm64); 0.5.0 and later
- `Headers/Open4IDSDK-Swift.h` — generated ObjC interface per slice
  (includes the `Open4IDLoginDialogObjC` facade with its iOS
  `UIViewController` and macOS `NSViewController` overloads, the
  `Open4IDGoogleAuthorizationCodeProviding` provider protocol, and the
  payments surface — the headless `payments()`/`entitlements()` API plus the
  built-in StoreKit store (`storeKitPayments`, `Open4IDStoreKitPayments`,
  `onTransactionUpdate`))
- `Headers/module.modulemap` + `Modules/module.modulemap` — Clang module
  over the generated interface (**0.8.8 and later**): `@import Open4IDSDK;`
  resolves in an Objective-C host with no search-path setup or
  `-fmodule-map-file` flag. The 0.3.3–0.7.0 binaries shipped no module map
  (the ObjC examples keep their `Open4IDSDKModule` adapter for those).
  Clean-room-verified: a SwiftPM consumer still resolves the Swift module
  from the `.swiftinterface` set with the map present.
- `Open4IDSDK.swiftmodule/` — module-stable `.swiftinterface` set

## What is new in 0.8.8

- **One event surface**: `client.onEvent` delivers every state change —
  `auth`, `products`, `entitlements`, `purchase`, `restore`, and
  `transaction` — in one block on the callback queue (main by default),
  replacing host-side re-publishing plumbing. Additive: the typed
  listeners still fire.
- **`subscriptionState(productId:)`**: `.active`, `.grace` (billing
  retry), `.expired`, `.none`, or `.unknown` for one catalog product —
  reads the live catalog and the catalog captured in the persisted
  snapshot, so it answers offline on a cold launch. Treat `.unknown` as
  *checking*, never "locked".
- **`start()`**: one-call launch (store adapter → bootstrap → launch
  restore → guest sign-in only when nothing was restored). Single-flight,
  retryable, and a stored session is never replaced by a guest.
- **Guest login split from the guest button**: `guest_enabled` stays the
  server capability; the new `guest_button_visible` flag only decides
  whether built-in dialogs render "Continue as guest" (defaults to the
  capability when absent — anonymous checkout is capability on, button
  off).
- **Purchase preflight**: the built-in store checks for a usable identity
  before opening the StoreKit sheet, so a misconfigured "login required"
  application fails with `client.auth.not_authenticated` instead of
  charging a player whose verify would be rejected. Hosts gate their shop
  with `canPurchase()` / `requiresSignIn()`.

Full list in `CHANGELOG.md` §0.8.8.

## How to verify and install

Grab the zip from the [latest release](https://github.com/open4id-community/ios-sdk/releases):

```bash
shasum -a 256 -c SHA256SUMS          # optional integrity check
unzip Open4IDSDK-1.0.0.xcframework.zip -d ~/open4id-ios-sdk
```

Then in Xcode: **General → Frameworks, Libraries, and Embedded Content →
Add… → Add Other → Add Files…** and pick
`~/open4id-ios-sdk/Open4IDSDK-1.0.0.xcframework` with **Embed & Sign** (for a
macOS target, Xcode selects the macOS slice automatically).

Please read `USER_GUIDE.md` for usage.
