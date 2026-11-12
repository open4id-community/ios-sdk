# macOS SDK Minimal IAP Example (Objective-C)

Objective-C twin of `examples/macos-sdk-minimal/`: a minimal **AppKit** app
that verifies Open4ID **App Store IAP** end to end through the Open4ID SDK's
**Objective-C surface** — the same `@objc` completion-handler API the Swift
sibling reaches through `async`/`await`. It links the SDK as the prebuilt
**XCFramework** at the repo root (`../../Open4IDSDK-0.8.8.xcframework`,
unzip the release asset there) with a Clang module-map adapter
(`Open4IDSDKModule/`) so `@import Open4IDSDK;` resolves against the static
library. Scoped to **payments only** — there is no login, social, session,
or account UI.

The payment feature lives in the SDK now — `client.storeKitPayments` (the
StoreKit 2 store) — so this sample is **pure Objective-C with zero Swift
files** and owns only its shop UI (Buy buttons per row, rendered from the
`Open4IDStoreProduct` rows the SDK returns; there is no shop view in the SDK
on purpose). StoreKit 2 is a Swift-only API, and the SDK owns that side; the
former `StoreKitBridge.swift` is gone.

> **2026-11-04:** the payment feature moved from this sample into the SDK.
> The former single Swift file (`StoreKitBridge.swift`) — and the whole
> "why one file must stay Swift" exception — is obsolete: the SDK's built-in
> store produces the proofs, runs the purchase pipeline, and registers the
> restore proof source.

## What it shows

- `configure` with validation errors returned as `NSError`
  (`NSErrorPointer` overload)
- `bootstrap` against the live Core API node
- `client.storeKitPayments` — one call that enables the built-in store:
  products from the SDK catalog request, the StoreKit purchase pipeline, and
  the automatic restore proof source
- `payments().products` — catalog snapshot, no network call
- `[Open4IDStoreKitPayments loadProducts:]` — StoreKit product resolution
  (prices) for the catalog rows, from pure ObjC
- **Buy buttons** rendered from the shop rows — the host-owned shop UI —
  each running `[Open4IDStoreKitPayments purchaseWithProductId:completion:]`
  (StoreKit sheet → JWS proof → verify → finish inside the SDK)
- `restore:` through the proof source the built-in store registered
  (`Transaction.currentEntitlements`)
- `entitlements` / `refresh:` — ledger recompute
- Live **Paid state** row (`entitlements.onChanged`): the SDK rehydrates
  paid state once per process after the first bootstrap, and the session
  persists in the Keychain by default — the same player (guest included)
  and their purchases come back after a relaunch or an uninstall/reinstall
- Errors as `NSError` with domain `Open4IDSDK`, the integer `error_code` as
  the code, and the stable key in `userInfo[@"key"]`
- Auto configure + bootstrap on launch; `OPEN4ID_AUTOTEST=payments` rehearsal

## Files

| File | Purpose |
|------|---------|
| `main.m` | Programmatic AppKit entry point |
| `AppDelegate.h/.m` | App delegate; holds the shared `Open4IDAuthClient`, builds the window |
| `ViewController.h/.m` | Main UI in pure ObjC: config fields, action buttons, log console, all SDK calls |
| `Info.plist` | App bundle config |
| `Open4IDSDKModule/` | Clang module map bridging the XCFramework's Swift-generated header so pure-ObjC consumers can `@import Open4IDSDK;`; the `Open4IDSDK-Swift.h` symlink targets the **macOS** slice's header |
| `macos-sdk-minimal-objc.xcodeproj/` | Xcode project (links `Open4IDSDK-0.8.8.xcframework` + `-fmodule-map-file` build setting) |

## Requirements

- macOS 13+ with Xcode 15+.
- Unzip the release asset at the repo root:
  `unzip Open4IDSDK-0.8.8.xcframework.zip -d .` — the example links
  `../../Open4IDSDK-0.8.8.xcframework`.

## Build & run

```sh
cd examples/macos-sdk-minimal-objc
open macos-sdk-minimal-objc.xcodeproj   # then Run (⌘R)
```

Command line:

```sh
xcodebuild -project macos-sdk-minimal-objc.xcodeproj -scheme macos-sdk-minimal-objc \
  -destination 'platform=macOS' build
```

On launch the app auto-configures and bootstraps, then logs:

```text
[open4id-iap] bootstrap ok: app=… payments=1
```

The log console mirrors to the unified log (subsystem
`com.open4id.example.macos`, category `iap`) and to
`~/Documents/open4id-log-objc.txt` (the Swift sibling writes
`open4id-log.txt`; the suffix keeps both from clobbering each other).

## ObjC API surface used

```objc
// Configure (NSErrorPointer overload; scope unused by IAP).
NSError *error = nil;
[client configureWithAppId:self.appIdField.stringValue
                environment:self.environmentField.stringValue
               publicSdkKey:self.publicSdkKeyField.stringValue
                   endpoint:self.endpointField.stringValue
                 redirectUri:self.redirectUriField.stringValue
                       scope:nil
                    bundleId:self.bundleIdField.stringValue
                       error:&error];

// One call enables the whole payment feature: the built-in StoreKit store
// (products from the SDK catalog request, purchase pipeline) and the
// automatic restore proof source. The namespace object is stable for the
// client's lifetime.
Open4IDStoreKitPayments *store = [client storeKitPayments];

// Bootstrap + headless namespaces (also stable).
[client bootstrap:^(Bootstrap *bootstrap, NSError *error) { … }];
self.payments = client.payments;          // Open4IDPayments *
self.entitlements = client.entitlements;  // Open4IDEntitlements *

// Catalog snapshot (no network call) and its app_store rows.
PaymentCatalog *catalog = [self.payments products];
self.appStoreProducts = [catalog forPlatform:@"app_store"];

// StoreKit product resolution (prices) through the built-in store; render
// one Buy button per row in your own UI.
[store loadProducts:^(NSArray<Open4IDStoreProduct *> *products,
                      NSError *error) { … }];

// One Buy button: the SDK runs the whole pipeline. Pass the catalog row you
// rendered the button from — no re-lookup, no stale-snapshot failure. Grant
// from the outcome.
[store purchase:product
     completion:^(Open4IDPurchaseOutcome *outcome, NSError *error) {
        if (outcome.isVerified) {
            // outcome.entitlements (one_time/subscription) or
            // outcome.receipt (consumable → grant by transactionRef).
        }
        // outcome.isCancelled / outcome.isPending are statuses, not errors.
    }];

// By id (e.g. from a deep link): looks the id up in the Open4ID catalog and
// refreshes the bootstrap once when the snapshot does not know it.
[store purchaseWithProductId:@"com.open4id.example.pkg_01"
    completion:^(Open4IDPurchaseOutcome *outcome, NSError *error) { … }];

// Restore through the proof source the store registered.
[self.payments restore:^(RestoreResult *result, NSError *error) { … }];

// Ledger recompute.
[self.entitlements refresh:^(EntitlementSnapshot *snapshot, NSError *error) { … }];
```

Errors surface as `NSError` with domain `Open4IDSDK`, the integer
`error_code` as the code, and the stable key in `userInfo[@"key"]` /
`NSLocalizedDescriptionKey` (e.g. `client.payment.invalid_request`).

> **Threading:** the SDK's `@objc` completion twins may fire on a background
> executor (they wrap the async surface in a `Task`), so every completion
> body in `ViewController.m` hops to the main queue before touching AppKit.
> The same applies to any ObjC host — wrap completion bodies in
> `dispatch_async(dispatch_get_main_queue(), …)` before updating UI.

> **Import note:** the SDK is consumed as a local *source* package here, so
> ObjC files `@import Open4IDSDK;` (same as `examples/ios-sdk-minimal-objc`).
> A remote *binary* XCFramework consumer instead ships
> `Open4IDSDK-Swift.h` for `#import` — and needs at least one Swift source
> in the consuming target for that quoted import to resolve.

## Payment testing (App Store)

Identical to the Swift sibling — the scheme's **Run** action references the
shared local StoreKit configuration (`examples/Open4IDStoreConfig.storekit`),
so the sample's Buy buttons show the StoreKit purchase sheet:

1. Run the app from Xcode (scheme StoreKit configuration active).
2. **Load shop (SDK store)** → the sample logs the catalog from the SDK
   request and renders the Buy buttons with StoreKit prices
   (`storekit: 3 products …`).
3. **Buy `com.open4id.example.pkg_01`** → confirm the StoreKit sheet → the
   SDK sends the `jwsRepresentation` to Core API:
   - `pkg_01` / `pkg_03` → `verifyTransaction` → entitlements;
   - `pkg_02` → `verifyConsumable` → `ConsumableReceipt`.
4. **Restore purchases** exercises the proof source the store registered;
   **Entitlements (ledger)** recomputes from the server ledger.

## Re-purchasing a subscription (`pkg_03`)

The three states a Buy on a subscription can land in, and what the log says:

1. **Subscription still active** (sandbox 1-month ≈ 5 minutes): Apple
   refuses the second purchase with its "You're currently subscribed to
   this" alert and returns `userCancelled` — no payment happens. The sample
   logs `cancelled by user` plus the Apple-refused hint. It becomes
   re-purchasable once the period lapses.
2. **Lapsed (expired) in the real sandbox**: Apple returns the existing
   lapsed transaction **without any sheet** — verified grant comes back
   `test_pk_03 [expired, expires=…]` plus the sample's no-sheet hint. This
   is a known Apple **sandbox limitation** (widely reported by developers),
   not a sample or SDK defect: the Buy button stays enabled and the
   pipeline runs; Apple just never starts a new payment.
3. **Production**: the resubscribe sheet shows normally and the new cycle
   verifies as `active` with a fresh `expires=`.

To re-test a fresh cycle locally:

- **Run via Xcode** with the scheme's StoreKit configuration active — the
  local StoreKit environment re-purchases an expired subscription with a
  fresh sheet and a new cycle (then verify answers `active`). Launching the
  built `.app` directly bypasses the configuration and hits the real
  sandbox, where limitation 2 applies; the sandbox sheet's
  `[Environment: Sandbox]` footer tells you which environment you are in.
- Or clear the sandbox tester's subscription history (App Store Connect →
  Users and Access → Sandbox → the tester → Clear Subscription History) and
  buy again against the real sandbox.

> **Endpoint matters for verification.** The sample defaults to the
> production node (`https://id.open4id.com/api`). Verification reads the
> Portal's **Payments → App Store → Bundle ID + Notification environment**
> for the `(app, environment)` the client asserts (`development` here) on
> **that deployment** — if they are missing there, every verify answers
> `503 client.payment.store_unavailable` (nothing reaches Apple — the
> Apple dialog itself still succeeds, because that part is client-side).
> Saving the `.p8` key to the Vault does **not** unblock verification (the
> Vault key is used by notifications/reconciliation — and the Portal form
> refuses to save while Apple is enabled but **Bundle ID / Issuer ID /
> Key ID** are empty, so pasting the `.p8` alone persists nothing). A 503
> that persists while another node **sharing the same database** verifies
> fine means the node itself is missing its pinned Apple root — the
> release must ship `priv/payment/apple_root_ca_g3.pem` (missing or
> mismatched file answers 503 before the JWS is read). To verify against a
> different Open4ID deployment (one where the application's App Store
> section is configured), set `OPEN4ID_ENDPOINT` accordingly (scheme
> **Run → Arguments → Environment Variables**, or edit the Endpoint
> field). A green server-side verify then still needs a real sandbox
> purchase — see the Swift sibling's store-environment notes.

For automation, launch with `OPEN4ID_AUTOTEST=payments`: the app logs the
catalog from the SDK request, loads the shop through
`client.storeKitPayments` `loadProducts:`, and buys the first resolvable row
(the StoreKit sheet still needs a human confirmation).

See the Swift sibling's README for the full store-environment notes:

- [What the local StoreKit config does and does not prove](../macos-sdk-minimal/README.md#what-the-local-storekit-config-does-and-does-not-prove)
  — the JWS verifies locally, but a green server-side verify needs a real
  sandbox/production store environment;
- [Portal prerequisites](../macos-sdk-minimal/README.md#portal-prerequisites)
  — macOS platform entry, SDK key, guest login,
  `payments.app_store.bundle_id`;
- the live runbook,
  [`docs/tasks/PAYMENT_LIVE_SMOKE_RUNBOOK.md`](../../docs/tasks/PAYMENT_LIVE_SMOKE_RUNBOOK.md).

## Configuration

Same fields and env overrides as the Swift sibling (`OPEN4ID_APP_ID`,
`OPEN4ID_ENVIRONMENT`, `OPEN4ID_SDK_KEY`, `OPEN4ID_ENDPOINT`,
`OPEN4ID_REDIRECT_URI`, `OPEN4ID_BUNDLE_ID`, set in the scheme's
**Run → Arguments → Environment Variables**). Defaults match the sibling:
dev application `app_4a17c6…`, environment `development`, bundle id
`com.open4id.example.ios` (universal purchase), ad-hoc signing.

## Notes

- The SDK's macOS support is described in
  [`sdks/ios/README.md`](https://github.com/open4id/open4id/blob/main/sdks/ios/README.md#macos-support): a native
  macOS target asserts `platform: "macos"`. This is a native macOS target,
  so it sends `macos`.
- No login runs here, so the app needs no URL-scheme callback and no
  `ASWebAuthentication` anchor; the SDK still requires a `redirectUri` value
  at `configure` time.
- Signing is ad-hoc ("Sign to Run Locally") with no sandbox entitlement,
  which is enough for the local StoreKit configuration. A real
  sandbox/production pass needs your own team, a registered bundle id, and a
  development or distribution signature.
- Unity/Unreal hosts: this sample is the closer template for a thin
  ObjC/ObjC++ plugin — the SDK calls stay in ObjC, and StoreKit 2 is the
  SDK's problem now (`storeKitPayments` + the `@objc` completion twins), not
  the host's (see
  [`sdks/ios/README.md`](../../sdks/ios/README.md#objective-c--unity-consumption)).
