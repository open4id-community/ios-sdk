# Open4ID iOS/macOS SDK (`Open4IDSDK`)

Swift headless auth client for Open4ID player authentication on iOS and macOS,
at parity with `@open4id/sdk` (JavaScript) and `com.open4id:open4id-sdk`
(Android): OAuth
Authorization Code + PKCE S256 against the Open4ID authorization server, with
opaque server-validated tokens. Games own their screens and call the headless
client; no provider credentials or OAuth secrets ever reach the app.

- Plan: [docs/tasks/MOBILE_SDK_IOS_PLAN.md](../../docs/tasks/MOBILE_SDK_IOS_PLAN.md)
- Execution task: [docs/tasks/MOBILE_SDK_IOS_TASK.md](../../docs/tasks/MOBILE_SDK_IOS_TASK.md)

## Status (2026-10-17)

**Released 2026-11-28: iOS/macOS SDK 1.0.3** — direct PayPal checkout and
license activation for macOS (iOS remains unavailable because mobile external
payments are disabled), plus publisher-defined events:
`trackEvent(_:value:)` (ObjC `trackEvent:` / `trackEvent:value:`) posts
`client/events`, the explicit counterpart of the automatic `appOpen()`
ping: batching (20 events or 10 s), retry on network/`429`/`5xx` with
`Retry-After`, an offline tail in `UserDefaults` (100 events / 7 days), an
app-hide flush plus optional `flushEvents()`, and the events-only
`setTrackingEnabled(false)` opt-out. At-least-once: a retry can inflate
counts. No properties in v1 — an optional numeric `value` only.

**Released 2026-10-20: first iOS SDK SPM release** — annotated tags
`v0.3.3` (plain semver, what SPM resolves) and `ios-v0.3.3` (SDK lineage
marker) at the same commit, which also adds a root `Package.swift` shim so
remote `.package(url:, from: "0.3.3")` works despite the manifest living in
`sdks/ios/`. Includes the Phase 13 login UI, the Phase 14 ObjC surface,
and the `Open4IDLoginDialogObjC` facade.

**Released 2026-10-23: iOS SDK 0.4.0** — `ios-v0.4.0` lineage tag;
Facebook sign-in (async + `@objc`), the Portal-origin `@objc` setter
(`setPortalOriginWithPortalOrigin:error:`), the web-session timeout
deadlock fix, provider-mark parity (Facebook glyph sized to the Apple
mark), and the prebuilt `Open4IDSDK-0.4.0.xcframework.zip` in `dist/`.
The plain-semver tag `v0.4.0` is on the GitHub SPM mirror
(`open4id-community/ios-sdk`), not in this monorepo (the monorepo's
`v0.4.0` belongs to the JS SDK lineage).

**Released 2026-11-02: iOS/macOS SDK 0.5.0** — `ios-v0.5.0` lineage tag;
headless payments and entitlements (`payments()` / `entitlements()`), App
Store consumables (`verifyConsumable(_:)` → `ConsumableReceipt`), and
first-class native macOS support (macOS 13+, `platform: "macos"`, AppKit
login helpers, and the macOS XCFramework slice). The prebuilt
`Open4IDSDK-0.5.0.xcframework.zip` is in `dist/`.

**Released 2026-11-04: iOS/macOS SDK 0.6.0** — built-in StoreKit 2 store
(`storeKitPayments()`), and the payments hardening batch (single-owner
bindings, reconcile sweep, purchase outcomes).

**Released 2026-11-12: iOS/macOS SDK 0.7.0** — `ios-v0.7.0` lineage tag;
the session persists by default (Keychain, surviving relaunch *and*
reinstall), paid state rehydrates once per process after the first
bootstrap (launch restore, reconciling with StoreKit receipts when a proof
source is registered), time-aware entitlement usability (`isUsable`
enforces `expiresAt` for `active` rows; `grace` stays server-owned),
`SessionStore`/`KeychainSessionStore` are `@objc` (no Swift shim for
Objective-C hosts), `Open4IDDiagnostics` opt-in logging, store facts
(`expirationDate`/`environment`) on the purchase outcome. 0.7.0 shipped no
Clang module map, so ObjC hosts used the examples' `Open4IDSDKModule`
adapter (see USER_GUIDE); **0.7.1 fixes that**. The prebuilt
`Open4IDSDK-0.7.0.xcframework.zip` is in `dist/`. The plain-semver tag
`v0.7.0` lives on the GitHub SPM mirror (`open4id-community/ios-sdk`), not
in this monorepo.

**Unreleased: iOS/macOS SDK 0.7.1** — restore chunks itself (20 proofs /
48 KiB per request, shape errors bisected, transients abort), a distinct
`client.payment.request_too_large` (`100005`) for both the new Core API
413 and the legacy 400/100003 shape, `SdkError.isRetryable` (also as
`retryable` in `NSError.userInfo`), and a Clang module map in every
XCFramework slice so `@import Open4IDSDK;` works with no build settings.

**Unreleased: iOS/macOS SDK 0.8.0** — paid state survives a relaunch: the
entitlement rows plus the catalog they were resolved against are persisted
(`SnapshotStore`, Keychain by default, `setSnapshotStore(nil)` opt-out) and
rehydrated inside `configure` (`isFromCache`/`savedAt`), cleared on sign-out,
`reset()`, and player switch. `start()` runs the documented startup order in
one call (store adapter → bootstrap → launch restore → guest sign-in) and is
single-flight and retryable; branch on `sessionState`
(`none`/`guest`/`authenticated`/`expired`) instead of `isAuthenticated()`,
and use `hasStoredSession()` for first-launch UI. Every listener now fires on
`setCallbackQueue(_:)` — the main queue by default, `nil` for synchronous
delivery. Full `swift test`: 234 tests, 1 skipped, 0 failures.

**Released 2026-11-12: iOS/macOS SDK 0.8.8** — one event surface instead of
four listeners: `onEvent` reports auth, catalog, entitlement, purchase,
restore, and StoreKit transaction changes as `Open4IDEvent`, on the callback
queue and additive to the typed listeners. `subscriptionState(productId:)`
answers paid state as `active`/`grace`/`expired`/`none`/`unknown` (offline
safe via the persisted catalog), replacing host-side recomputation from
`isPurchased`. Full `swift test`: 249 tests, 1 skipped, 0 failures.

**Released 2026-11-15: iOS/macOS SDK 1.0.0** — `ios-v1.0.0` lineage tag; the
first 1.0: interactive restore for "Restore purchases"
(`restoreInteractive()` / ObjC `restoreInteractive:`, `AppStore.sync()` first
so a signed-out account gets the store sign-in sheet, typed
`SdkStoreSignInCancelledError` `140007`, additive
`RestoreResult.storeSynced`), app-open analytics (`appOpen()` with a
Keychain-persisted installation id riding every payment call),
bearer-proved player calls (`deleteAccount`/`linkEmail`/`getUser`) rotate a
stale access token before the request, and the honest
"this store account owns none of our products" answer for a completed sync
with `verified == 0`. Device-verified on an iPhone 12 against the App Store
sandbox (all six restore cases). Full `swift test`: 271 tests, 1 skipped,
0 failures. The prebuilt `Open4IDSDK-1.0.0.xcframework.zip` is in `dist/`.
The plain-semver tag `v1.0.0` lives on the GitHub SPM mirror
(`open4id-community/ios-sdk`), not in this monorepo.

**Released 2026-11-21: iOS/macOS SDK 1.0.2** — `ios-v1.0.2` lineage tag;
guest authorization requests include the persisted installation `device_id`,
preserving the guest identity across repeated sign-in on the same
installation. Player API request bodies consistently carry the existing
`device_id` attribution field. The prebuilt
`Open4IDSDK-1.0.2.xcframework.zip` is in `dist/`.

**All 12 plan phases executed.** Phases 2–11 built and verified; the
phase-12 interactive pass ran on a real iPhone (iOS 27.0.1): live bootstrap
with the native binding, the on-device attestation posture row, two full
social sign-in round-trips with verified emails, and account deletion.

- `swift build` green, zero warnings; `swift test` green (97 tests,
  including real host-keychain round-trips; no web session is presented in
  unit tests). Full suite on the iOS Simulator via `xcodebuild test`:
  97 executed, 0 failures, 3 keychain skips. The same host run builds and
  tests the macOS target; the six live-fixture ObjC integration tests skip
  on macOS because the shared development application registers only an iOS
  bundle id.
- Implemented: `Open4IDAuthClient` with full `configure` validation, redacted
  `getConfig`, portal-origin handling, auth-state listeners, session-store
  restore, and the complete runtime — live-proven `bootstrap()` (native
  `platform: "ios"` + `bundle_id` shape on iOS, `platform: "macos"` +
  `bundle_id` on native macOS, verified against the dev Core API
  node), `buildAuthorizationUrl`/`handleCallback` (PKCE S256 redirect
  flow), `completeAuthorization` machinery (single-use code exchange,
  generation guard), single-flight `refresh()` with reuse clearing the
  session, `getUser()`, `ensureSession(minValidity:)`, local-clearing
  `signOut()` with best-effort server revocation, the opt-in
  server-callback receipt (fresh sign-ins only, gated on the enabled flag;
  manual `notifyServer()`), the player flows
  (`signInWithPassword`, `continueAsGuest`, `register`/
  `resendVerification`/`verifyEmail`, `requestPasswordReset`/
  `resetPassword`, `linkEmail`, `deleteAccount`), and the Android-mirrored
  social flows: `signInWithGoogle` (host-overridable seam; no headless
  default on iOS), `signInWithGitHub`/`signInWithFacebook`/
  `signInWithApple` (real `ASWebAuthenticationSession` defaults through
  the Portal bridges, state=nonce for Apple, `access_denied` on
  denial/mismatch).

## Social providers (Android-mirrored)

- **Google** — override `getGoogleAuthorizationCode` (subclass the `open`
  client) and return a fresh server auth code issued for the bootstrap Web
  client ID; typed errors surface unchanged. The base seam reports
  `provider_unavailable` (no Play-Services analogue on iOS).
- **GitHub** — the SDK opens the authorize URL (`read:user user:email`)
  in an `ASWebAuthenticationSession`; the Portal bridge hands `?code&state`
  back to the `<bundleId>://open4id/github-callback` deep link; the SDK
  posts `github_code` + the exact `github_redirect_uri`.
- **Facebook** — the SDK opens the pinned (`v26.0`) OAuth dialog
  (`scope=email`) at `facebook.com` in an `ASWebAuthenticationSession`;
  the Portal bridge hands `?code&state` back to the
  `<bundleId>://open4id/facebook-callback` deep link; the SDK posts
  `facebook_code` + the exact `facebook_redirect_uri` (register the
  per-app Portal bridge URL in the Facebook app's Valid OAuth Redirect
  URIs). Requires a granted email: players who decline the email
  permission fail closed at exchange time.
- **Apple** — same session flow with `scope=email` + `response_mode=form_post`
  (the Portal bridge answers the form_post); the OAuth nonce doubles as
  state and nonce; the SDK posts `apple_code` + the exact
  `apple_return_uri`.
- Web flows need `setPresentationAnchor` (the presenting window) and honor
  `setPrefersEphemeralWebSessions`; timeouts map to `client.auth.popup_timeout`,
  user-close to `popup_closed`, missing anchor to `popup_blocked`.
- Pending: live device smoke on a real hardware device (phase 12 — the
  simulator pass and all host-side verification are complete). The
  attestation probe reports device capability honestly (a real `passed`
  verdict needs the not-yet-contracted `attestKey` challenge handshake);
  the DeviceCheck fallback policy stays an open question with the Product
  Owner.

## Requirements

- iOS 16+, macOS 13+ (the same sources build for both; macOS is a
  first-class target, not only a host for unit tests).
- Swift 5.9+ toolchain; zero third-party runtime dependencies
  (Foundation, CryptoKit, Security, URLSession only).

## macOS support

Register `macos` as a platform for your application in the Publisher Portal
(General → Platform identifiers), using the Mac app's bundle id. A native
macOS target then sends `platform: "macos"` on bootstrap and every player
request; Mac Catalyst keeps sending `ios` because it ships the iOS binary.
The SDK selects the value automatically from the build target — do not set it
by hand.

- The Core API compares the asserted `bundle_id` with the enabled `macos`
  entry, so the Mac App Store app needs a `macos` platform entry (share the
  bundle id with the iOS entry under universal purchase, or register a
  distinct bundle id).
- StoreKit 2 payment verification is unchanged: the App Store record uses
  `payments.app_store.bundle_id`, and the JWS `bundleId` must match it.
- `Open4IDAuthView` and `Open4IDLoginDialog` render on macOS. AppKit hosts
  use `showOpen4IDLoginDialog(on: NSViewController, model:)` (or the
  `Open4IDLoginDialogObjC` facade with an `NSViewController`), presented as a
  sheet; SwiftUI hosts keep `.open4IDLoginSheet(isPresented:model:)`.
- Social sign-in uses `ASWebAuthenticationSession` on macOS too; supply the
  presenting window through `setPresentationAnchor` (it is an `NSWindow` on
  macOS, a `UIWindow` on iOS).
- `Scripts/build-xcframework.sh` emits an additional `macos` slice for
  AppKit hosts alongside the iOS device and simulator slices.
- [`examples/macos-sdk-minimal`](../../examples/macos-sdk-minimal) is a native
  macOS SwiftUI sample that verifies App Store IAP through the SDK's built-in
  payments feature (`storeKitPayments()`; shared
  `examples/Open4IDStoreConfig.storekit` as the scheme's local test fixture).
- [`examples/macos-sdk-minimal-objc`](../../examples/macos-sdk-minimal-objc)
  is the same macOS IAP sample in pure Objective-C: AppKit UI and every SDK
  call through the `@objc` completion surface — the SDK's built-in store owns
  the Swift-only StoreKit 2 side, so the target needs no Swift file at all.

## Quick start (Swift)

Add the package in Xcode (File → Add Package Dependencies…) or in
`Package.swift` — the repository root manifest (shipped with the SDK tag)
makes remote resolution work even though the full manifest lives at
`sdks/ios/Package.swift`:

```swift
// Recommended for 0.7.0: the GitHub SPM mirror (plain v0.7.0 tag, binaryTarget
// resolving the prebuilt zip — Swift sources stay private).
.package(url: "https://github.com/open4id-community/ios-sdk", from: "0.7.0")
```

Internal monorepo consumers resolve through the root-manifest shim as
before; the monorepo carries no plain `v<version>` tag for SDK releases
(the plain-semver tags go to the GitHub SPM mirror), so internal consumers
resolve the mirror exactly like external ones.

```swift
.package(url: "ssh://git@gitsvr.ddns.net:2222/n/open4id.git", from: "0.3.3")
```

> Tags: the SDK release marker is `ios-v0.7.0` (lineage). SPM itself only
> accepts plain-semver tags, so consumer resolution pins the plain `v0.7.0`
> tag published on the GitHub mirror repo `open4id-community/ios-sdk` —
> a separate namespace from the monorepo's JS SDK tags.

```swift
import Open4IDSDK

let auth = Open4IDAuthClient()

try auth.configure(
    appId: "app_...",
    environment: "production",          // development | sandbox | production
    publicSdkKey: "sdk_pk_...",          // public by design; never a secret
    redirectUri: "com.example.game://open4id/callback",
    bundleId: "com.example.game"
)

let bootstrap = try await auth.bootstrap()   // phase 5
let session = try await auth.signInWithPassword(email: "player@example.com",
                                                password: "correct-horse")

auth.getSession()
auth.isAuthenticated()
try await auth.refresh()
try await auth.signOut()

// App-open analytics (optional, fire-and-forget — never throws):
await auth.appOpen()          // cold-start ping → dashboard opens/devices
let deviceId = auth.deviceIdentifier()  // Keychain-persisted installation id
Open4IDAuthClient.resetDeviceId()       // debug/support reset hook
```

The installation id is a random UUID minted locally and persisted in the
Keychain (`com.open4id.sdk.device`), so it survives relaunches and
reinstalls. It is attribution metadata, not a credential: the server stores
only a salted hash, and every payment call rides the same id beside the
session (`device_id`/`device_platform`) — the money path never depends on
it.

### Publisher events (`trackEvent`)

`appOpen()` is automatic tracking. `trackEvent()` is the explicit one: call
it when something the publisher cares about happened, and the Portal's
**Events** tab charts it. Nothing calls it for you, and it never touches the
install/open/MAU numbers.

```swift
auth.trackEvent("level_completed")                    // count
auth.trackEvent("level_completed", value: 42)         // numeric aggregate
auth.trackingEnabled                                  // true unless opted out
auth.setTrackingEnabled(false)                        // opt out, clears the queue
await auth.flushEvents()                              // send now (optional)
```

- **Name**: lowercase snake_case, 2–40 characters. `open4id.*` is reserved
  for automatic tracking and is refused, as are arbitrary properties — v1
  stores a numeric `value` only (`|value| <= 1e9`). Objective-C hosts call
  `trackEvent:` (no value) or `trackEvent:value:` (`NSNumber`).
- **Pre-declared keys**: the Events tab is an allow-list — create the
  event in the Portal first. The server silently discards entries whose
  key is not a declared, active event (the batch answers with the
  discarded count in `rejected`); siblings still write.
- **Buffering**: events are queued and sent in batches of up to 20, at most
  10 s after the first one. 100 events / 7 days survive in `UserDefaults`
  (key `open4id.events.<appId>`; event names, timestamps, and numbers are
  telemetry, not credentials, so the Keychain stays reserved for the
  session), so a process death does not lose the tail; `configure()` replays
  what the previous process buffered.
- **Attribution**: when a session exists the batch carries its bearer, so
  the event is attributed to the player (`last_user_id`). A signed-out or
  stale session never blocks the send.
- **Delivery**: transient failures (network, `429`, `5xx`) retry up to five
  times with backoff, honouring `Retry-After`; permanent ones (`400`, `401`,
  `413`) drop the batch. Core API is at-least-once here, so a retry can
  inflate counts — treat the numbers as usage trends, not an audit trail.
- **Never blocks or throws**: `trackEvent()` enqueues and returns. An
  uninitialized client, an invalid name/value, and every server error are
  absorbed.
- **Opting out**: `setTrackingEnabled(false)` clears the buffered and
  persisted event queue and stops sends. It does **not** affect `appOpen()`,
  which stays a per-call host decision. The switch covers publisher events
  only.

Or run the whole startup sequence in one call — store adapter, bootstrap,
launch restore, guest sign-in — and branch on the honest session state:

```swift
let session = try await auth.start()
switch auth.sessionState {
case .guest, .authenticated, .expired: startGame(session)
case .none: showSignIn()
}
```

`start()` is single-flight, retryable, and never replaces a stored session
with a guest; `.expired` still means a session exists (the SDK rotates the
token on the next call). `hasStoredSession()` reports whether a previous
process persisted a session.

Every `async` method also has an Objective-C completion-handler twin:

```swift
auth.start { session, error in
    // error bridges to NSError (domain "Open4IDSDK", code = error_code)
}
```

## Objective-C / Unity consumption

The public surface is deliberately ObjC-bridgable (`NSObject` classes,
completion handlers, `NSError` domain/code/userInfo), because the SDK ships
into other games/apps:

- **Swift + SPM**: add this package as a dependency of your app target
  (`examples/ios-sdk-minimal` shows exactly this).
- **Objective-C / legacy apps**: consume the XCFramework distribution —
  `Scripts/build-xcframework.sh` builds three slices (iOS device +
  simulator + macOS) with **library evolution** enabled: the
  `.swiftinterface` set carries toolchain-stable ABI and the generated
  `Open4IDSDK-Swift.h` ObjC interface ships per slice. A Swift SPM package
  is not directly callable from Objective-C; the XCFramework is.
- **Unity/Unreal**: write a thin ObjC/ObjC++ plugin against the XCFramework
  surface — the same pattern used by other Swift game SDKs. Bindings are out
  of v1 scope by plan.

### Objective-C quick start

Prebuilt binaries for publishers live in `sdks/ios/dist/`
(`Open4IDSDK-0.7.0.xcframework.zip` + `SHA256SUMS`, built by
`Scripts/build-xcframework.sh` at the release tag — see
`dist/README.md` for verify/unzip/install steps). Otherwise build locally:

Add `Open4IDSDK.xcframework` to your Xcode project (General → Frameworks,
Libraries, and Embedded Content → `Embed & Sign`), then import and use:

```objc
@import Open4IDSDK;
// 0.7.1+ XCFramework: every slice ships a Clang module map, so this import
// needs no search paths or flags. With an SPM source package or a
// pre-0.7.1 artifact, use: #import <Open4IDSDK/Open4IDSDK-Swift.h> instead.

Open4IDAuthClient *auth = [[Open4IDAuthClient alloc] init];
NSError *error = nil;
[auth configureWithAppId:@"app_..."
             environment:@"development"
         publicSdkKey:@"sdk_pk_..."
                endpoint:@"https://id.open4id.com/api"
            redirectUri:@"com.example.game://open4id/callback"
                   scope:@"openid profile email"
               bundleId:@"com.example.game"
                  error:&error];
if (error) {
    // error.domain == @"Open4IDSDK", error.code == integer error_code,
    // error.userInfo[@"key"] == stable key (e.g. "client.auth.invalid_request")
    return;
}

// Listen to login-state changes (sign-in, sign-out, refresh, delete).
void (^unsubscribe)(void) = [auth onAuthStateChanged:^(AuthSession * _Nullable session,
                                                        UserInfo * _Nullable user) {
    if (session) {
        NSLog(@"signed in: %@", session.userId);
    } else {
        NSLog(@"signed out");
    }
}];

// Sign in as guest.
[auth continueAsGuest:^(AuthSession * _Nullable session, NSError * _Nullable error) {
    if (!error) {
        NSLog(@"guest session: %@", session.userId);
    }
}];

// Sign out.
[auth signOut:^(NSError * _Nullable error) {
    if (!error) {
        NSLog(@"signed out");
    }
}];
```

Every `async` Swift method has an `@objc` completion-handler twin (e.g.
`bootstrap:`, `signInWithPasswordWithEmail:password:completion:`,
`continueAsGuest:`, `refresh:`, `signOut:`). Errors bridge as `NSError`
with domain `Open4IDSDK`, the integer `error_code` as the code, and the
stable key (`client.auth.*`, `system.*`, `sdk.*`) in `userInfo[@"key"]`.

The generated `Open4IDSDK-Swift.h` header exposes all public model types
(`AuthSession`, `UserInfo`, `Bootstrap`, `AuthDiscovery`, `ProviderRef`,
`LoginReadiness`, `ServerCallback`, `ServerCallbackReceipt`, `SessionSnapshot`)
with their properties readable from ObjC.

> **Note:** `RedactedConfig` (returned by `getConfig`) is a nested Swift type
> and is not exposed to ObjC; check that `getConfig()` returns non-nil after
> `configure` succeeds. The SwiftUI `ui/` layer (Phase 13 login view/dialog)
> is not directly reachable from ObjC (global Swift functions and the
> non-`@objc` `Open4IDAuthViewModel` are invisible to the generated header);
> pure ObjC hosts open the login dialog through the `@objc` facade below.

#### Login dialog from ObjC (Phase 13 UI via facade)

Since Phase 14, the SDK ships `Open4IDLoginDialogObjC`
(`ui/Open4IDLoginDialogObjCBridge.swift`) — an `@objcMembers` facade that
performs the same binding the SwiftUI hosts do (locale, `setAuthClient`,
`setBootstrap`, sign-in mode) and presents the same centered-card login
dialog over UIKit — dimmed backdrop, tap-outside dismiss, auto-close on
sign-in (`dismissOnSignIn: YES`), session-aware account view:

```objc
// Store the bootstrap from `[auth bootstrap:...]` — it drives the
// provider list (nil hides providers/guest until re-bound).
self.lastBootstrap = bootstrap; // inside the bootstrap completion handler

Open4IDLoginDialogHandleObjC *handle = [Open4IDLoginDialogObjC
    showOn:self                                  // any UIViewController
    client:auth                                  // configured headless client
    bootstrap:self.lastBootstrap
    localeTag:@"en"                              // en/vi; nil = en
    dismissOnSignIn:YES
    onSignedIn:^(NSString *provider) { NSLog(@"signed in %@", provider); }
    onSignedOut:^{ NSLog(@"signed out"); }
    onAccountDeleted:^{ NSLog(@"account deleted"); }];

// Imperative close, mirroring the Android dialog's close():
[handle close];                                  // optional
```

Google/GitHub/Facebook/Apple inside the card use the same client — set
`setPresentationAnchor` (and the Google provider via
`setGoogleAuthorizationCodeProvider:` for ObjC hosts) before opening the
dialog. Working reference: `examples/ios-sdk-minimal-objc` (Login UI
section, verified on the iOS 27.1 simulator).

The recipe is verified end-to-end on this repository's machine (see the
phase-11 handoff section in the task file). The ObjC integration test target
(`Tests/Open4IDSDKObjCIntegrationTests`) proves configure → bootstrap →
sign-in → auth-state listener → refresh → sign-out → delete from pure ObjC;
run it via `xcodebuild test` (swift's CLI test sandbox has no network, so
network-dependent flows only pass under `xcodebuild test` against the
simulator or when the live node is reachable).

## Payments and entitlements (headless)

The headless surface is the payments contract: hosts that own their store
client (Unity IAP, a custom StoreKit bridge) buy through their
store and forward the proof here; Core API re-verifies it with Apple before
granting an entitlement. The SDK has no `verifyReceipt` fallback. Only
`app_store` proofs are submitted from iOS and macOS; the Android SDK owns
`google_play`.

For the one-call built-in StoreKit store — the
feature the example apps used to own — see
[Payments the easy way](USER_GUIDE.md#payments-the-easy-way-built-in-store)
in the user guide. The short version:

```swift
// One call enables the built-in StoreKit 2 store: shop rows from the Open4ID
// catalog request, the full purchase pipeline (StoreKit sheet → JWS proof →
// verify → Transaction.finish()), a self-sufficient restore (built-in proof
// source over Transaction.currentEntitlements), and a Transaction.updates
// listener (ask-to-buy approvals and cross-device buys are verified,
// finished, and reported via store.onTransactionUpdate). The shop UI stays
// the host's — render the rows yourself.
let store = auth.storeKitPayments()
let outcome = try await store.purchase(productId: "com.example.premium")
```

The headless contract is unchanged:

```swift
// Catalog comes from the bootstrap snapshot (no network call).
let catalog = auth.payments().products()
if catalog.enabled {
    for product in catalog.forPlatform(PaymentProvider.appStore) {
        // product.productId / product.type / product.entitlements
    }
}

// After StoreKit reports a verified transaction, forward its JWS.
let proof = try TransactionProof.appStore(
    productId: "com.example.premium",
    jwsRepresentation: transaction.jwsRepresentation)
let rows = try await auth.payments().verifyTransaction(proof)

// Restore/recompute from the server ledger. Proofs are optional and
// additive; an invalid proof counts as `rejected`, a proof owned by an
// anonymous player transfers the purchase to this one, and a proof owned
// by a credentialed account counts as `conflict`.
let result = try await auth.payments().restore()
// result.entitlements / result.verified / result.rejected / result.conflict
// result.hasConflict / result.proofsUnavailable

// Optional but recommended: one registration makes restore() self-sufficient
// at app start and behind "Restore purchases". The source is a store client
// the host already owns, so the SDK stays dependency-free. (The built-in
// store — `auth.storeKitPayments()` — registers its own source over
// `Transaction.currentEntitlements` automatically.)
final class StoreProofs: PaymentProofSource {
    func collectProofs(_ completion: @escaping ([TransactionProof], Error?) -> Void) {
        Task {
            var proofs: [TransactionProof] = []
            for await entry in Transaction.currentEntitlements {
                // verified StoreKit 2 transaction
                if case .verified(let transaction) = entry {
                    proofs.append(try TransactionProof.appStore(
                        productId: transaction.productID,
                        jwsRepresentation: transaction.jwsRepresentation))
                }
            }
            completion(proofs, nil)
        }
    }
}
auth.payments().proofSource = StoreProofs()

// Cheap checks against the cached snapshot.
let snapshot = try await auth.entitlements().refresh()
let premium = auth.entitlements().has("premium") // active or grace
let all = auth.entitlements().list()
let unsubscribe = auth.entitlements().onChanged { snapshot in
    // verify, restore, refresh, sign-in, sign-out
}
```

Every call has an `@objc` completion-handler twin
(`verifyTransaction(_:completion:)`, `restore(_:)`,
`restore(proofs:completion:)`, `refresh(_:)`), and `PaymentProofSource` is an
`@objc` protocol so Objective-C hosts can implement the source too.

### Events and subscription state

One block replaces a host-side event bus. `onEvent` reports every SDK state
change the typed listeners cover, plus the outcomes they cannot observe
(catalog loads, restore summaries, StoreKit update results):

```swift
auth.onEvent = { event in
    switch event.kind {
    case .auth:         // success + message ("guest", "google", ...)
    case .products:     // message "catalog:8" or "store:8"
    case .entitlements: // entitlements (empty + success:false = cleared)
    case .purchase:     // productId, message "verified" / a consumable state / an error key
    case .restore:      // message "verified=2 rejected=0 conflict=0"
    case .transaction:  // ask-to-buy approval or cross-device buy
    @unknown default: break
    }
}

// Paid state without recomputing from isPurchased per product id:
let state = auth.subscriptionState(productId: "com.example.premium")
// .active / .grace / .expired / .none / .unknown
```

Events are delivered on the callback queue (`setCallbackQueue(_:)`, main by
default) and state is already settled when the block runs. `onEvent` is
additive: `onAuthStateChanged`, `entitlements().onChanged`, and
`storeKitPayments().onTransactionUpdate` keep firing, so a host can migrate
one path at a time. Set the block before `configure` to see the first
bootstrap events.

`subscriptionState` reads the live catalog first and falls back to the
catalog stored with the paid-state snapshot, so it answers offline after a
cold launch. It distinguishes billing retry (`.grace`) from expiry and from
"never bought" (`.none`), and returns `.unknown` when there is no snapshot
yet, the product is in neither catalog, or it is a consumable (no
entitlement keys). Show `.unknown` as *checking*, never as "locked".

### Consumables

Both stores sell consumables. The shared catalog parses a `consumable` row
faithfully (`isConsumable`, empty `entitlements`) and refuses a consumable that
names an entitlement, in either store. `verifyConsumable(_:)` takes an
`TransactionProof.appStore(productId:jwsRepresentation:)` and returns a
`ConsumableReceipt` — the server re-verifies the JWS, records the delivery on
the Open4ID ledger (Apple has no server-side consume, so the ledger is the only
consume record and its `already_delivered` replay guard is the receipt's
anti-duplication defense), and the game grants items keyed by
`receipt.transactionRef`. Grant only from `delivered` or `already_delivered`;
`pending` means retry the verify, `refunded` means the purchase was reversed.

`verifyTransaction` remains for the entitlement path; when its response carries
a `delivery` block (a consumable payload) it skips the entitlement publish, so
an empty entitlement list cannot wipe the cached snapshot. The Google Play
proof path of `verifyConsumable`, server-side store consumption, and
partial-refund reconciliation are documented in the Android SDK README
(`sdks/android/README.md`).

Rules and shapes:

- **Proofs**: `TransactionProof.appStore(productId:jwsRepresentation:)`.
  The JWS is sent once, never logged, and never persisted;
  `description` redacts it.
- **States**: `active` and `grace` are usable; `expired` and `revoked`
  stay in `list()` so the host can show history. `expiresAt` is `nil`
  for non-expiring one-time grants.
- **Snapshot lifecycle**: the cached snapshot is cleared when the
  signed-in player changes or signs out, so grants never leak across
  sessions. Same-session transitions keep it. On a cold start the SDK
  rehydrates the persisted rows + catalog inside `configure`
  (`isFromCache`/`savedAt`), so `current()` is already readable offline;
  "no snapshot" still means unknown, not "not purchased".
- **Callbacks**: listeners (`entitlements().onChanged`,
  `onAuthStateChanged`, `storeKitPayments().onTransactionUpdate`,
  `onServerCallbackError`) fire on the queue set with
  `setCallbackQueue(_:)` — the **main queue** by default,
  `setCallbackQueue(nil)` for synchronous delivery. State is settled
  before the callback runs.
- **Restore bounds**: the SDK chunks restores itself — at most 20 proofs
  and 48 KiB of serialized JSON per request — so a large catalog restores
  completely. You never need to split or truncate the proof list. Core API
  reads at most 262144 bytes on the client payment routes (`65536` on
  releases before 0.7.1) and answers a larger body with
  `client.payment.request_too_large` (`100005`, HTTP 413).
- **Catalog fail-closed**: before bootstrap, when the application has no
  store enabled, or when the block is missing/malformed,
  `products().enabled` is `false` with an empty list.
- **Retries**: `160003` (`client.payment.store_unavailable`) is
  transient — retry later. A `503` on **every** verify is not transient. On
  the App Store path it has two per-node causes: **(1)** the Portal's
  Payments → App Store section is not saved for the `(app, environment)`
  the client asserts (`payments.app_store.bundle_id` empty — a missing
  config, a disabled provider, or an unknown product would answer
  `400 invalid` instead); **(2)** the node cannot load its pinned Apple root — the
  release must ship `priv/payment/apple_root_ca_g3.pem`, and a missing or
  mismatched file (SHA-256 ≠ the pin in `lib_payment_app_store.erl`)
  answers 503 **before the JWS is read**. When another node sharing the
  same database verifies fine, the config is correct and cause (2) is the
  one. The Vault `.p8` key is not consulted by verification at all —
  StoreKit 2 JWS verification is local against the pinned Apple root; the
  key matters only for notifications and App Store Server API
  reconciliation. `140006` (`client.payment.owned_by_another_account`)
  means the purchase is bound to another account: ask the player to sign
  in as that account, do not retry.
- **Guest purchases and store-account restore**: `verifyTransaction` and
  `restore` sign in as a guest first when there is no session and the
  bootstrap snapshot allows guest login; with guest login disabled they throw
  `client.auth.not_authenticated`. A store-verified proof moves the purchase
  only while the current owner is still an anonymous guest, so a reinstall or
  a fresh guest recovers what it paid for. Once an owner has an email or
  social identity the purchase is sticky: verify throws `SdkConflictError` and
  restore reports `result.conflict`, so a shared Apple ID can never take a
  grant away from the paying account.
- **App lifecycle and restore**: the device stores the session, never the
  grants. At app start the SDK schedules a **passive** restore
  (`payments().restore()`): it recomputes the ledger for the restored session
  and re-submits the store proofs the device already holds (idempotent). It
  reads `Transaction.currentEntitlements` only — it never asks the store
  account and never prompts — so after a reinstall with no store account
  signed in it legitimately recovers nothing and raises no sheet.
  A **"Restore purchases" button** must call
  `Open4IDStoreKitPayments.restoreInteractive()` (ObjC
  `restoreInteractive:`). That runs `AppStore.sync()` first — the call that
  raises the App Store sign-in sheet and refreshes the local receipt — then
  the same ledger restore. A completed sync marks `result.storeSynced = true`,
  so `verified == 0` honestly means "this store account owns none of our
  products" instead of the passive path's "nothing cached". A dismissed sheet
  throws `SdkStoreSignInCancelledError` (`140007`,
  `client.payment.store_sign_in_cancelled`) **before** any ledger request;
  any other sync failure is `SdkStoreUnavailableError` (`160003`, retryable).
  The store account is independent of the signed-in player: the sync reads
  whatever App Store account the device has, even a different Apple ID than
  the one that bought. If that account holds a purchase the ledger already
  bound to **another** account with an email or social identity, Core API
  refuses the transfer and the result carries it in `result.conflict`
  (`verified` stays 0, no error); a purchase bound to an anonymous guest is
  moved to the signed-in player.
  Both are distinct from `result.proofsUnavailable`, which stays reserved for
  "the proof source could not be read" (error or the 10 s bound). Set
  `payments().proofSource = <PaymentProofSource>` once with the StoreKit
  client you already own and both restores share it; without a source, restore
  stays a ledger-only recompute. Use `entitlements().refresh()` when only the
  ledger matters, and explicit `restore(proofs:)` when the host collects
  proofs itself — neither consults the source. Consumables never appear in
  `currentEntitlements` and an expired subscription drops out of it, so
  neither can be restored: re-deliver consumables through
  `verifyConsumable`, and treat a lapsed subscription as a new purchase.
- **Token freshness**: `verifyTransaction`, `restore`, and
  `entitlements().refresh()` rotate a stale access token through
  `ensureSession` before the call, so a session older than the 900 s token
  lifetime (a store sheet left open, an idle game) still works instead of
  throwing `auth.token.invalid`. The other bearer-proved player calls do the
  same — `deleteAccount()`, `linkEmail(email:password:)`, and `getUser()` —
  so account deletion or linking does not fail with a 401
  (`client.player.invalid` on the wire) once the token has aged out. None of
  them mints a guest; signed out, they throw
  `client.auth.not_authenticated` as before.

## Errors

Typed hierarchy; branch on the stable key or integer code, never on text:

| Type | Code | Notes |
| --- | --- | --- |
| `SdkValidationError` | `100003` | `fieldErrors` map (`appId`, `redirectUri`, ...) |
| `SdkAuthError` | `110003` | invalid key/credentials (`110005`), verify-required (`120001`), token failures |
| `SdkNotFoundError` | `130004` | Unknown payment transaction or entitlement |
| `SdkConflictError` | `140006` | Purchase bound to another credentialed account (`client.payment.owned_by_another_account`); restore reports it as `conflict` instead |
| `SdkStoreSignInCancelledError` | `140007` | Player dismissed the App Store sign-in/purchase sheet during `restoreInteractive()` (`client.payment.store_sign_in_cancelled`); no ledger request was made, not retryable |
| `SdkRateLimitedError` | `150001` | `retryAfterSec` (-1 when unknown) |
| `SdkUnavailableError` | `160001` | Core API/transport down |
| `SdkStoreUnavailableError` | `160003` | Store verification temporarily unavailable (retryable; subclasses `SdkUnavailableError`) |
| `SdkInternalError` | `170001` | unexpected failure |
| `SdkNotImplementedError` | `-1` | method awaits its implementation phase |

Stable keys mirror the sibling SDKs (`client.auth.*`, `system.*`, `sdk.*`),
e.g. `client.auth.not_authenticated`, `client.auth.invalid_request`,
`client.auth.provider_unavailable`, `sdk.not_initialized`.

As `NSError`: domain `Open4IDSDK`, code = the integer `error_code`, and
userInfo carries `key`/`error_code` (+ `field_errors`, `retry_after_sec`).

## Storage

| Backend | Default | Notes |
| --- | --- | --- |
| `MemorySessionStore` | no (opt-out) | lost on process death; pass it to `configure(store:)` or `setSessionStore(nil)` |
| `KeychainSessionStore` | yes | generic-password item per `service`/`account`,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; corrupt payloads map
  to "nothing stored"; best-effort — failures never break sign-in
  (`lastStatus` for diagnostics) |
| `MemorySnapshotStore` | when the session store is memory-only | paid state (entitlement rows + catalog) in memory only |
| `KeychainSnapshotStore` | yes | paid state per player (`account.playerId`), same accessibility as the session item; survives relaunches and reinstalls |

Paid state is hydrated inside `configure`, so a cold launch can answer
`entitlements().has(_:)`/`isPurchased(productId:)` before the first network
read; those rows are flagged `EntitlementSnapshot.isFromCache` with
`savedAt`. Sign-out, `reset()`, and a player switch clear only the departing
player's cache. Opt out with `setSnapshotStore(nil)` (the Keychain default
also follows the session store: a `MemorySessionStore` keeps paid state in
memory).

Tokens are never written to `UserDefaults` and never logged (descriptions
redact token values; keys redact to the last four characters). Store proofs
(JWS) are never persisted.

## Security rules

- `sdk_pk_...` is public application material; `sdk_sk_...`, OAuth client
  secrets, Apple private keys, and Vault references never enter the SDK.
- Player tokens are opaque and server-validated; the SDK never parses or
  locally validates a JWT and never publishes/receives JWKS material.
- Redirect URIs are exact-match registered values; native apps use custom
  schemes (`com.example.game://open4id/callback`) behind the Portal bridges.
- No WebView is ever used for authentication.

## Development

```sh
cd sdks/ios
swift build      # compiles the macOS target (iOS slices build via Xcode)
swift test       # 302 tests: 293 run on macOS, 9 skip (opt-in live probes,
                 # live-fixture ObjC integration tests)
```
