# macOS SDK Minimal IAP Example

Minimal SwiftUI **macOS** app that verifies Open4ID **App Store IAP**
end to end with the released headless SDK. It resolves the SDK from the
published GitHub Swift package
(`https://github.com/open4id-community/ios-sdk`, `from: "0.5.0"`), not from a
local checkout. It is the macOS twin of `examples/ios-sdk-minimal`, scoped to
**payments only** — there is no login, social, session, or account UI.

> **Status 2026-11-02:** the macOS App Store IAP path is live-verified end to
> end against Core API (server-side JWS verification).

It reuses the iOS sample's payment pieces verbatim:

- **StoreKit 2 bridge** (`Open4IDStoreKitBridge.swift`) — StoreKit 2 is the
  same framework on macOS;
- **Open4ID IAP catalog** (`Open4IDStoreConfig.storekit`) — the same three dev
  products: `com.open4id.example.pkg_01` one-time,
  `com.open4id.example.pkg_02` consumable, `com.open4id.example.pkg_03`
  subscription.

What the app does: bootstrap (loads the payment catalog and enables the guest
session a purchase needs), then buy/verify a catalog row through
`payments().verifyTransaction` / `verifyConsumable`, plus
`restore()` (proof source over `Transaction.currentEntitlements`) and
`entitlements().refresh()`.

## Requirements

- macOS 13+ with Xcode 15+.
- The app resolves `Open4IDSDK` from the published GitHub Swift package
  `https://github.com/open4id-community/ios-sdk`, rule **Up to Next Major**
  from `0.5.0` (pinned in `Package.resolved`). Run once with network access so
  Xcode fetches the binary XCFramework; no local SDK checkout is needed.

## Build & run

```sh
cd examples/macos-sdk-minimal
open macos-sdk-minimal.xcodeproj   # then Run (⌘R)
```

Command line:

```sh
xcodebuild -project macos-sdk-minimal.xcodeproj -scheme macos-sdk-minimal \
  -destination 'platform=macOS' build
```

On launch the app auto-configures and bootstraps, then logs:

```text
open4id-iap: bootstrap ok: app=… payments=true
```

The log console mirrors to the unified log (subsystem
`com.open4id.example.macos`) and to `~/Documents/open4id-log.txt`.

## Payment testing (App Store)

The scheme's **Run** action references the local StoreKit configuration
(`Product` → StoreKit configuration), so **Load payments catalog** resolves the
three dev products and each **Buy `…`** button shows the StoreKit purchase
sheet.

1. Run the app from Xcode (scheme StoreKit configuration active).
2. **Load payments catalog** → logs the Open4ID catalog and StoreKit prices
   (`storekit: 3 products …`).
3. **Buy `com.open4id.example.pkg_01`** → confirm the StoreKit sheet → the
   bridge sends the `jwsRepresentation` to Core API:
   - `pkg_01` / `pkg_03` → `verifyTransaction` → entitlements;
   - `pkg_02` → `verifyConsumable` → `ConsumableReceipt`.
4. **Restore purchases** exercises the SDK's registered `PaymentProofSource`
   (`Transaction.currentEntitlements`); **Entitlements (ledger)** recomputes
   from the server ledger.

For automation, launch with `OPEN4ID_AUTOTEST=payments` to auto-run catalog
load + StoreKit product resolution + a purchase of the first one-time row (the
sheet still needs a human confirmation).

### What the local StoreKit config does and does not prove

Xcode's local StoreKit configuration drives **client-side** product resolution
and the purchase UI (the JWS verifies locally, so the bridge reaches the
Open4ID `verify*` call). It is **not** a real store transaction: Core API
re-verifies the JWS against Apple, and a locally-generated test JWS carries
`environment: "Xcode"`, which no `sandbox`/`production` application accepts.
A green server-side `verify ok: … entitlement(s)` therefore needs a **real
store environment**:

- Sign the Mac into a **Sandbox Apple ID** (App Store → sign in with a Sandbox
  Tester account) and register the app in App Store Connect with the products
  enabled, then run a development-signed build; or
- Run a production build with real products.

Use the local config to prove the wiring, and a sandbox/production purchase to
prove verification end to end. See the live runbook,
[`docs/tasks/PAYMENT_LIVE_SMOKE_RUNBOOK.md`](../../docs/tasks/PAYMENT_LIVE_SMOKE_RUNBOOK.md).

### Portal prerequisites

The sample defaults assume the Open4ID application is configured for macOS:

- **General → Platform identifiers**: enable **macOS** with the app's bundle id.
  This sample uses the universal-purchase identity — the same bundle id
  (`com.open4id.example.ios`) in both the `ios` and `macos` entries.
- **SDK keys**: the public SDK key must allow the `macos` platform.
- **Login methods**: **guest login** must be enabled — a purchase with no
  session signs in as a guest automatically.
- **Payments → App Store**: set the bundle id (`payments.app_store.bundle_id`)
  and the store environment; Core API compares the JWS `bundleId` with that
  value, so it must match the Mac app's bundle id.

The sample bundle id, app id, and SDK key ship as development placeholders —
point them at your own registered app (see the env overrides below).

## Configuration

| Field | Default |
| --- | --- |
| App ID | dev application `app_4a17c6…` |
| Environment | `development` |
| Public SDK key | dev key (must allow `macos`) |
| Endpoint | `https://app.open4id.com/api` |
| Bundle ID | `com.open4id.example.ios` (universal purchase: same bundle id as the iOS app) |
| Redirect URI | `com.open4id.example.ios://open4id/callback` (required by `configure`, unused by IAP) |

Every field can be overridden at launch so an alternate-app run needs no source
edit — set these in the scheme's **Run → Arguments → Environment Variables**:

```text
OPEN4ID_APP_ID, OPEN4ID_ENVIRONMENT, OPEN4ID_SDK_KEY, OPEN4ID_ENDPOINT,
OPEN4ID_REDIRECT_URI, OPEN4ID_BUNDLE_ID
```

## Notes

- The SDK's macOS support is described in
  [`sdks/ios/README.md`](../../sdks/ios/README.md#macos-support): a native
  macOS target asserts `platform: "macos"` (Mac Catalyst keeps `ios`). This is
  a native macOS target, so it sends `macos`.
- No login runs here, so the app needs no URL-scheme callback and no
  `ASWebAuthentication` anchor; the SDK still requires a `redirectUri` value at
  `configure` time.
- Signing is ad-hoc ("Sign to Run Locally") with no sandbox entitlement, which
  is enough for the local StoreKit configuration. A real sandbox/production
  pass needs your own team, a registered bundle id, and a development or
  distribution signature.
