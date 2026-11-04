# macOS SDK Minimal IAP Example

Minimal SwiftUI **macOS** app that verifies Open4ID **App Store IAP**
end to end with the SDK's **built-in payment feature**. It resolves the SDK
from the local Swift package (`../../sdks/ios`, the same convention as
`examples/ios-sdk-minimal`). It is the macOS twin of `examples/ios-sdk-minimal`,
scoped to **payments only** — there is no login, social, session, or account
UI.

> **Status 2026-11-02:** the macOS App Store IAP path is live-verified end to
> end against Core API (server-side JWS verification).
>
> **2026-11-04:** the payment feature moved from this sample into the SDK —
> `client.storeKitPayments()` (StoreKit 2 store). The sample owns **no store
> code** anymore; the former `Open4IDStoreKitBridge.swift` is gone. The shop
> UI stays host-owned by design (the SDK ships no shop view): this sample
> renders its own Buy buttons from the `Open4IDStoreProduct` rows the SDK
> returns.

What the app does: bootstrap (loads the payment catalog and enables the guest
session a purchase needs), then **Load shop** pulls the rows from the SDK's
built-in store — shop rows from the Open4ID catalog request joined with
StoreKit prices — and one **Buy** button per row runs the SDK's purchase
pipeline (StoreKit sheet → JWS proof → `verifyTransaction` /
`verifyConsumable` → `Transaction.finish()`). Restore runs through the proof
source the store registered automatically. The headless **Restore purchases**
and **Entitlements (ledger)** buttons stay for automation logs.

## Requirements

- macOS 13+ with Xcode 15+.
- The app references the SDK as a **local Swift package**
  (`../../sdks/ios`) — no registry dependency.

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

The whole flow needs no host store code. The sample renders the shop itself:

1. Run the app from Xcode (scheme StoreKit configuration active — see below).
2. **Load shop (SDK store)** → the sample logs the catalog from the SDK
   request and renders one Buy button per row with the StoreKit prices
   (three dev rows `com.open4id.example.pkg_01`–`pkg_03`).
3. **Buy** a row → confirm the StoreKit sheet → the SDK sends the
   `jwsRepresentation` to Core API:
   - `pkg_01` / `pkg_03` → `verifyTransaction` → entitlements;
   - `pkg_02` → `verifyConsumable` → `ConsumableReceipt`.
4. **Restore purchases** exercises the proof source the SDK registered
   (`Transaction.currentEntitlements`); **Entitlements (ledger)** recomputes
   from the server ledger.

> **Endpoint matters for verification.** The sample defaults to the
> production node (`https://id.open4id.com/api`). Verification reads the
> Portal's **Payments → App Store → Bundle ID + Notification environment**
> for the `(app, environment)` the client asserts (`development` here) on
> **that deployment** — if they are missing there, every verify answers
> `503 client.payment.store_unavailable` and nothing reaches Apple. Saving
> the `.p8` key to the Vault does **not** unblock verification (the Vault
> key is used by notifications/reconciliation, and the Portal form refuses
> to save while Apple is enabled but **Bundle ID / Issuer ID / Key ID** are
> empty, so pasting the `.p8` alone persists nothing). A 503 that persists
> while another node **sharing the same database** verifies fine means the
> node itself is missing its pinned Apple root — the release must ship
> `priv/payment/apple_root_ca_g3.pem` (missing or mismatched file answers
> 503 before the JWS is read). For local-stack runs
> set `OPEN4ID_ENDPOINT` = `http://localhost:10001/api` (scheme **Run →
> Arguments → Environment Variables**, or edit the Endpoint field). A green
> server-side verify then still needs a real sandbox purchase — see "What
> the local StoreKit config does and does not prove" below.

For automation, launch with `OPEN4ID_AUTOTEST=payments`: the app logs the
catalog from the SDK request, loads the shop through
`client.storeKitPayments().loadProducts()`, and buys the first resolvable row
(the StoreKit sheet still needs a human confirmation).

### What the local StoreKit config does and does not prove

Xcode's local StoreKit configuration (`examples/Open4IDStoreConfig.storekit`,
referenced by the scheme's **Run** action) drives **client-side** product
resolution and the purchase UI (the JWS verifies locally, so the SDK reaches
the Open4ID `verify*` call). It is a **development fixture only** — a normal
user of the SDK never authors one. It is **not** a real store transaction:
Core API re-verifies the JWS against Apple, and a locally-generated test JWS
carries `environment: "Xcode"`, which no `sandbox`/`production` application
accepts. A green server-side `verify ok: … entitlement(s)` therefore needs a
**real store environment**:

- Sign the Mac into a **Sandbox Apple ID** (App Store → sign in with a Sandbox
  Tester account) and register the app in App Store Connect with the products
  enabled, then run a development-signed build; or
- Run a production build with real products.

Use the local config to prove the wiring, and a sandbox/production purchase to
prove verification end to end. See the live runbook,
[`docs/tasks/PAYMENT_LIVE_SMOKE_RUNBOOK.md`](https://github.com/open4id/open4id/blob/main/docs/tasks/PAYMENT_LIVE_SMOKE_RUNBOOK.md).

### Sandbox subscription time (`pkg_03`)

Apple compresses subscription durations in the sandbox: a 1-month
subscription expires about **5 minutes** after purchase and auto-renews up to
twelve times (~1 hour) before it stops renewing. Two consequences the log
makes visible (each entitlement line now carries `expires=`):

- A fresh sandbox buy answers `test_pk_03 [active]` with an expiry ~5 minutes
  out; re-read it later and the state has moved on to `expired` — the ledger
  is simply reporting what Apple signed.
- **Re-buying an owned subscription shows no purchase sheet.** When the
  sandbox store account already owns `pkg_03` (active or lapsed), Apple's
  `purchase()` returns the existing transaction silently and re-subscribes —
  that is Apple's behavior, not a missing step in the sample. A lapsed
  subscription comes back `expired` (the sample logs a
  `storekit: no sheet shown …` hint when this happens). To re-test the
  sheet and a fresh cycle, clear the tester's subscription history
  (App Store Connect → Users and Access → Sandbox Testers → the tester →
  Clear Subscription History, or the device's sandbox account management)
  and buy again.

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
| Endpoint | `https://id.open4id.com/api` (local dev node `http://localhost:10001/api` available for local-stack runs — see the note above) |
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
  [`sdks/ios/README.md`](https://github.com/open4id/open4id/blob/main/sdks/ios/README.md#macos-support): a native
  macOS target asserts `platform: "macos"` (Mac Catalyst keeps `ios`). This is
  a native macOS target, so it sends `macos`.
- No login runs here, so the app needs no URL-scheme callback and no
  `ASWebAuthentication` anchor; the SDK still requires a `redirectUri` value at
  `configure` time.
- Signing is ad-hoc ("Sign to Run Locally") with no sandbox entitlement, which
  is enough for the local StoreKit configuration. A real sandbox/production
  pass needs your own team, a registered bundle id, and a development or
  distribution signature.
