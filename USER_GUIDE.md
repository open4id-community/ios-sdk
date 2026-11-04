# Open4ID iOS SDK — User Guide

Welcome to the Open4ID iOS SDK (`Open4IDSDK`), a Swift authentication SDK for
Open4ID player identity in iOS and macOS games and apps. This guide walks
producers through installation, configuration, sign-in, and the operational
details needed to ship to the App Store and the Mac App Store.

For a condensed reference, see [README.md](README.md). For support, open an
issue at <https://github.com/open4id-community/ios-sdk/issues>.

**At a glance:**

- OAuth 2.0 Authorization Code + PKCE (S256) against the Open4ID
  authorization server — no web views, no OAuth secrets in the app.
- Opaque, server-validated tokens; the SDK never parses or trusts a JWT
  locally.
- Full API parity with the Open4ID JavaScript (`@open4id/sdk`) and Android
  (`com.open4id:open4id-sdk`) SDKs.
- Works from Swift (async/await), Objective-C (completion handlers +
  `NSError`), and Unity/Unreal-style engines through the XCFramework
  surface.
- Optional prebuilt login-dialog UI with English/Vietnamese localization.

## Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Project setup](#project-setup)
4. [Configure the client](#configure-the-client)
5. [Sign players in](#sign-players-in)
6. [Login dialog (built-in UI)](#login-dialog-built-in-ui)
7. [Social providers](#social-providers)
8. [Session management](#session-management)
9. [Player account flows](#player-account-flows)
10. [Delegate verification to your server (server callback)](#delegate-verification-to-your-server-server-callback)
11. [Payments the easy way (built-in store)](#payments-the-easy-way-built-in-store)
12. [Payments and entitlements (headless)](#payments-and-entitlements-headless)
13. [Payments in Objective-C](#payments-in-objective-c)
14. [Error handling](#error-handling)
15. [Token storage](#token-storage)
16. [Security model](#security-model)
17. [Objective-C and Unity notes](#objective-c-and-unity-notes)
18. [Troubleshooting](#troubleshooting)

## Requirements

| Item | Requirement |
|------|-------------|
| Minimum deployment target | iOS 16.0, macOS 13.0 |
| Toolchain | Swift 5.9+ toolchain (a current Xcode release) |
| Dependencies | None — Foundation, CryptoKit, Security, and URLSession only |

## Installation

### Swift Package Manager (recommended)

In Xcode: **File → Add Package Dependencies…** and enter:

```
https://github.com/open4id-community/ios-sdk
```

Use the version rule **Up to Next Major** from `0.5.0`. SDK releases are
tagged with plain semver tags (`v0.5.0` on the mirror repo), which is what
SPM resolves.

In `Package.swift`, the equivalent is:

```swift
dependencies: [
    .package(url: "https://github.com/open4id-community/ios-sdk", from: "0.5.0")
]
```

Then in your app target, add the `Open4IDSDK` product to **Frameworks and
Libraries**.

### Binary XCFramework (Objective-C / legacy apps / Unity)

If you cannot use SPM (Objective-C projects, Unity and Unreal integrations),
download the prebuilt `Open4IDSDK-<version>.xcframework.zip` and its
`SHA256SUMS` from the
[latest GitHub release](https://github.com/open4id-community/ios-sdk/releases),
then:

```bash
shasum -a 256 -c SHA256SUMS          # optional integrity check
unzip Open4IDSDK-0.5.0.xcframework.zip -d ~/open4id-ios-sdk
```

In Xcode: **General → Frameworks, Libraries, and Embedded Content →
Add… → Add Other → Add Files…** and pick the extracted `Open4IDSDK.xcframework`,
set to **Embed & Sign**.

The XCFramework contains both the device slice (`ios-arm64`) and the
simulator slice (`ios-arm64_x86_64-simulator`), built with library evolution
enabled so the binary remains ABI-stable across future Xcode
toolchains.

A Swift package resolved via SPM is not directly callable from Objective-C —
choose SPM consumption for Swift apps and the XCFramework for
Objective-C and game-engine apps.

## Project setup

Before configuring the client, you need the following values from the
Open4ID producer console:

| Value | Example | Notes |
|-------|---------|-------|
| **App ID** | `app_9f3ab2c1` | Identifier of your registered app (`app_` prefix). |
| **Public SDK key** | `sdk_pk_xV7...` | Public by design; safe to embed in the client. Never use a secret key (`sdk_sk_...`) here. |
| **Redirect URI** | `com.example.game://open4id/callback` | Custom scheme, exact match with the value registered for your app. |

Also register the custom scheme in Xcode so the OS routes the redirect back
to your app: **Target → Info → URL Types → URL Schemes** — set the **URL
Scheme** to your bundle id (e.g. `com.example.game`) and leave **Role** as
`Viewer`. On macOS, add the same scheme under **Target → Info → URL Types**
(or `CFBundleURLTypes` in `Info.plist`); AppKit delivers the callback through
your app delegate's `application(_:open:)` / `NSAppleEventManager` handling,
so forward it to the SDK the same way an iOS host forwards the URL.

Finally, in **Signing & Capabilities**, enable **Keychain Sharing** if you
opt into the Keychain session store, and ensure the app target includes the
push/entitlements you expect. No additional capabilities are required for
authentication.

## Configure the client

The client owns the session lifecycle. Create exactly one
`Open4IDAuthClient` for your app and configure it early (e.g. in
`application(_:didFinishLaunchingWithOptions:)` or `App.init()`):

```swift
import Open4IDSDK

let auth = Open4IDAuthClient()

try auth.configure(
    appId: "app_9f3ab2c1",
    environment: "production",                 // development | sandbox | production
    publicSdkKey: "sdk_pk_xV7...",             // public by design; never a secret
    redirectUri: "com.example.game://open4id/callback",
    bundleId: "com.example.game"
)
```

Parameters:

- **environment** — selects the backend environment: `production` for App
  Store builds, `sandbox` for pre-release testing against a staging
  backend, and `development` for local integration work.
- **scope** — optional. Defaults to `openid profile email`, which covers
  identity claims and the player email. If you pass your own, it must still
  include `openid`.
- **endpoint** — optional override; leave at the default
  `https://id.open4id.com/api` for production. A custom endpoint is only
  valid when the environment is not `production`.
- **bundleId** — your app's bundle id. Enable the matching `ios` or `macos`
  platform entry for the application in the Publisher Portal. The SDK derives
  the wire `platform` from the build target: native macOS sends `macos`,
  while Mac Catalyst and iOS send `ios`. You never pass `platform` yourself.

After `configure` succeeds, `getConfig()` returns a **redacted** snapshot of
the effective settings (the SDK key is masked to its last four characters).
Use it in logs or checks instead of holding raw credentials:

```swift
if let snapshot = auth.getConfig() {
    print("configured:", snapshot.environment, snapshot.endpoint)
}
```

## Sign players in

### Swift / async-await

Follow these steps in order:

1. **Bootstrap** — performs the native application handshake
   (`platform: "ios"` + `bundle_id` on iOS and Mac Catalyst, `platform:
   "macos"` + `bundle_id` on native macOS). It fetches app metadata, provider
   availability, and login readiness, and drives the provider buttons in
   the UI. Re-run it on each app launch. A `401` here usually means the
   platform entry or bundle id does not match the application configuration.

2. **Pick a flow** — password, guest, or one of the social flows.

3. **Manage the session** — read state, refresh, persist tokens, sign out.

```swift
do {
    // 1. Bootstrap (required once per launch before using flows/UI).
    let bootstrap = try await auth.bootstrap()

    // 2. Sign in.
    // (a) Email + password.
    let session1 = try await auth.signInWithPassword(
        email: "player@example.com",
        password: "correct-horse")
    let user1 = try await auth.getUser()
    print("Signed in as \(user1.email ?? "<no email>") ("\(session1.userId)")")

    // (b) Or sign in as a guest (anonymous account, can link email later).
    let session2 = try await auth.continueAsGuest()

    // 3. Session lifecycle.
    print(auth.getSession()?.userId)          // current session or nil
    print(auth.isAuthenticated())             // true while token is fresh
    print(auth.isGuestSession())              // true for guest sign-ins
    _ = try await auth.refresh()              // rotates the token; single-flight
    let session3 = try await auth.ensureSession(minValidityMs: 60_000) // refresh only if near expiry
    try await auth.signOut()                  // clears local session; revokes server-side if possible
} catch let error as SdkError {
    // Stable error keys and numeric codes — see [Error handling](#error-handling).
    print("auth error (code \(error.code)): \(error.key)")
}
```

> **Non-persisted by default:** the default in-memory store loses the
> session when the process exits. To keep players signed in across launches,
> pass the Keychain adapter to `configure`:
>
> ```swift
> try auth.configure(
>     ...,
>     store: KeychainSessionStore())
> ```
>
> The adapter stores one generic-password Keychain item per `service`/
> `account` pair; pass `account:` to namespace sessions when one process
> embeds more than one client.

### Objective-C

Every `async` Swift API ships a completion-handler twin callable from
Objective-C. Import the SDK's generated ObjC interface header first — the
direct-header import works in every consumption path (SPM package and
XCFramework); `@import Open4IDSDK;` works only in some SPM setups (pure
Objective-C targets with a source package), so prefer the header import.
Errors surface as `NSError` with domain `Open4IDSDK`, code set
to the integer error code, and the stable key in `userInfo[@"key"]`
(`client.auth.*`, `system.*`, `sdk.*`):

```objc
#import <Open4IDSDK/Open4IDSDK-Swift.h>
// SPM builds the product as a static library; the generated header sits on
// the header search path, so the quoted form also works: #import "Open4IDSDK-Swift.h"

Open4IDAuthClient *auth = [[Open4IDAuthClient alloc] init];
NSError *error = nil;
[auth configureWithAppId:@"app_9f3ab2c1"
              environment:@"production"
          publicSdkKey:@"sdk_pk_xV7..."
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

// Bootstrap, then sign in as guest.
[auth bootstrap:^(Bootstrap * _Nullable bootstrap, NSError * _Nullable error) {
    [auth continueAsGuest:^(AuthSession * _Nullable session, NSError * _Nullable error) {
        if (!error) {
            NSLog(@"guest session: %@", session.userId);
        }
    }];
}];

// Sign out.
[auth signOut:^(NSError * _Nullable error) {
    if (!error) {
        NSLog(@"signed out");
    }
}];
```

## Login dialog (built-in UI)

The SDK includes a ready-made login view so you do not have to build screens
yourself yet. Two flavors ship in the package:

- **`Open4IDAuthView`** — SwiftUI card view: email/password sign-in,
  registration, guest button, provider buttons, forgot-password, email
  verification, session, and account deletion. Localized in English
  (`en`) and Vietnamese (`vi`).

- **`Open4IDLoginDialog`** — a drop-in dialog wrapper: dimmed backdrop,
  tap-outside dismiss, automatic close on sign-in (configurable, sign-out
  keeps it open so the user can sign in again).

### SwiftUI hosting

Bind an `Open4IDAuthViewModel` to your configured client and bootstrap
before opening the UI — the view model renders provider availability and
sign-in mode off that state:

```swift
import Open4IDSDK

@State private var authModel = Open4IDAuthViewModel()
@State private var showLogin = false

func openLogin() {
    authModel.setLocale("en")                       // "en"/"vi", default en
    authModel.setAuthClient(auth)                   // the configured client
    authModel.setBootstrap(auth.getBootstrap())     // last bootstrap snapshot
    authModel.setMode(.signIn)                      // sign-in vs. sign-up mode
    showLogin = true
}
```

Embed the card view directly in your SwiftUI hierarchy:

```swift
Open4IDAuthView(model: authModel)
```

Or present it as a center-screen dialog:

```swift
.open4IDLoginSheet(isPresented: $showLogin, model: authModel)
```

After each successful `bootstrap()`, refresh the view model with
`authModel.setBootstrap(auth.getBootstrap())` so the provider buttons stay
current.

### UIKit hosting (same SwiftUI dialog, imperative open/close)

```swift
let close = showOpen4IDLoginDialog(on: self /* UIViewController */, model: authModel)
// later:
close()
```

### AppKit hosting (macOS sheet)

```swift
let close = showOpen4IDLoginDialog(on: self /* NSViewController */, model: authModel)
// later:
close()
```

The macOS helper presents the same card as a sheet over the given view
controller. SwiftUI hosts use the same `.open4IDLoginSheet(isPresented:
model:)` modifier on both platforms.

### Pure Objective-C hosting

Since the SwiftUI view itself is not reachable from Objective-C, the
SDK exposes the `Open4IDLoginDialogObjC` facade (part of the
XCFramework's generated header) that presents the same dialog:

```objc
// Keep the Bootstrap from [auth bootstrap:...] — it drives the
// provider list (nil hides providers/guest until re-bound).
Open4IDLoginDialogHandleObjC *handle = [Open4IDLoginDialogObjC
    showOn:self                                  // UIViewController, or NSViewController on macOS
    client:auth                                  // configured headless client
    bootstrap:self.lastBootstrap
    localeTag:@"en"                              // en/vi; nil = en
    dismissOnSignIn:YES
    onSignedIn:^(NSString *provider) { NSLog(@"signed in %@", provider); }
    onSignedOut:^{ NSLog(@"signed out"); }
    onAccountDeleted:^{ NSLog(@"account deleted"); }];

// Imperative close, mirroring the Android dialog's close():
[handle close];
```

Google/GitHub/Facebook/Apple inside the dialog use the same client — set
`setPresentationAnchor` (and, for Google, `setGoogleAuthorizationCodeProvider:`
for ObjC hosts) before opening it.

## Social providers

The SDK mirrors the Android provider surface exactly. Custom-scheme deep
links go through the Open4ID Portal bridge, which returns the per-provider
callback URL to the SDK. The SDK handles opening, state/nonce generation,
and code exchange.

### Apple, GitHub, and Facebook — built-in

`signInWithApple`, `signInWithGitHub`, and `signInWithFacebook` use
`ASWebAuthenticationSession` over the Open4ID Portal bridges. All are
first-party APIs on iOS and macOS, so the SDK owns the browser round-trip
itself:

- GitHub scopes: `read:user user:email`; posts `github_code` + the
  registered `github_redirect_uri`.
- Facebook: the OAuth dialog at `facebook.com` (pinned Graph API
  version, `scope=email`); the SDK posts `facebook_code` + the
  registered `facebook_redirect_uri`. The callback URI must be
  registered in the Facebook app's *Valid OAuth Redirect URIs* — the
  Portal shows the exact per-bundleId bridge URL
  (`<portalOrigin>/facebook-callback/<bundleId>`, or the origin-derived
  `<redirect-origin>/facebook-callback` for https redirect URIs). The
  granted email is required: a player who declines the email permission
  fails closed at the exchange (`invalid_grant`).
- Apple: `scope=email` + `response_mode=form_post`; the OAuth
  `nonce` doubles as state for anti-replay; posts `apple_code` + the
  registered `apple_return_uri`.
- Timeout (120 s) maps to the error key `client.auth.popup_timeout`;
  user-cancellation maps to `popup_closed`; a missing presentation anchor
  maps to `popup_blocked`.

Before using web-based providers, configure the presentation anchor and
optionally ephemeral sessions:

```swift
auth.setPresentationAnchor { /* getter returning your UIWindow (iOS) or NSWindow (macOS) */ }
auth.setPrefersEphemeralWebSessions(true) // no cookie carry-over; recommended
```

### Google — host-provided code

iOS has no Play-Services analogue, so `signInWithGoogle` requires the host
to obtain a **Google server authorization code** for the SDK and hand it
in. The default implementation reports `client.auth.provider_unavailable`.

Override the seam by subclassing the client (Swift route):

```swift
final class GameAuthClient: Open4IDAuthClient {
    override func getGoogleAuthorizationCode(
        clientId: String,
        timeoutMs: Int) async throws -> String {
        // Present GTM/AppAuth or server-side flow; return a fresh
        // authorization code issued for this app's Web client ID.
        try await GoogleCodeFetcher().authorizationCode(for: clientId)
    }
}
```

Whichever route you choose, return **one** fresh code — codes are
single-use and a replay surfaces as a typed
`client.auth.invalid_request` (or `access_denied` on provider denial) just
like the other flows.

For pure Objective-C hosts (which cannot subclass a Swift class), implement
the `Open4IDGoogleAuthorizationCodeProviding` protocol in ObjC and register
it before presenting sign-in:
```objc
// GameAuthClient: an ObjC class conforming to Open4IDGoogleAuthorizationCodeProviding
[auth setGoogleAuthorizationCodeProvider:[[GameAuthProvider alloc] init]];
```

### Callback deep links

GitHub, Facebook, and Apple flows return control to your app through the
portal-callback custom scheme in the registered redirect URI
(`<bundleId>://open4id/github-callback`, `<bundleId>://open4id/facebook-callback`,
`<bundleId>://open4id/apple-callback`).
Make sure the bundle-id scheme is registered in **Info → URL Types** (see
[Project setup](#project-setup)); without it the `ASWebAuthenticationSession`
times out and you see `popup_timeout`.

## Session management

### Observing state

`onAuthStateChanged` fires on every session transition (sign-in, sign-out,
refresh, account deletion), across all sources:

```swift
let unsubscribe = auth.onAuthStateChanged { session, user in
    if let session {
        print("signed in \(session.userId)")
    } else {
        print("signed out")
    }
}
// later:
unsubscribe()   // unregistration returns a closure that cancels the listener
```

The same listener shape exists in ObjC (see
[Sign players in](#sign-players-in)).

### Refresh and validity

- `isAuthenticated()` checks token freshness locally (with a 30 s expiry
  skew) — useful for gating UI.
- `refresh()` rotates the token. Concurrent callers coalesce into a single
  flight. If the refresh token has been used elsewhere, the SDK clears the
  local session and surfaces a typed error — never a partially swapped
  state.
- `ensureSession(minValidityMs:)` refreshes only when the token is inside
  the validity window; call it before routing a player to gameplay.

The SDK is thread-safe: an internal generation guard serializes flows, so
a token exchange and a refresh started concurrently cannot clobber each
other or interleave session generations.

## Player account flows

Beyond sign-in, the SDK covers the complete account surface; all of these
are also available from ObjC via the `@objc` twins:

| Method | Purpose |
|--------|---------|
| `register(email:password:)` | Create a new player account. |
| `resendVerification(email:)` | Re-send the email-verification message. |
| `verifyEmail(token:)` | Complete email verification (`token` comes from the verification link). |
| `requestPasswordReset(email:)` | Send a password-reset email. |
| `resetPassword(token:newPassword:)` | Finish the reset using the emailed token. |
| `linkEmail(email:password:)` | Attach an email/password identity to the **current guest** session. |
| `deleteAccount()` | Permanently delete the signed-in account (confirm before calling; the change is irreversible). |

Guest sessions become upgrades through `linkEmail`; regular accounts already
own their email.

## Delegate verification to your server (server callback)

For games where sensitive entitlements (purchases, bans, leaderboards) are
verified by your own backend, the SDK can deliver a signed receipt of a
**fresh sign-in** to that server automatically.

The behavior is driven by the bootstrap snapshot: only when your app has
the server callback **enabled** (as configured in the producer console) do
fresh sign-ins trigger the best-effort delivery and return a
`ServerCallbackReceipt`. Everything is optional turn-off; if disabled
nothing happens.

To opt in manually (e.g. re-delivering after a failed attempt):

```swift
do {
    try await auth.notifyServer()
} catch {
    // usually network errors or misconfiguration; the session itself is unaffected
}
```

Best-effort means that a delivery failure never invalidates the session —
listen for it separately:

```swift
let unsubscribe = auth.onServerCallbackError { error in
    // error.key, error.code — handle/log, the session stays valid
}
```

## Payments the easy way (built-in store)

Since 0.6.0 the SDK ships the StoreKit 2 glue that hosts previously wrote by
hand (the sample apps' `StoreKitBridge`): a built-in headless store client.
One client call enables everything — products loaded from the Open4ID catalog
request, the full purchase pipeline, and a self-sufficient restore. The shop
UI stays yours: render the rows the SDK returns however your game wants.

```swift
let auth = Open4IDAuthClient()
try auth.configure(/* ... */)
let bootstrap = try await auth.bootstrap()

// One call: built-in StoreKit 2 store. It reads the app_store rows of the
// Open4ID catalog (the bootstrap snapshot), resolves StoreKit products,
// registers the restore proof source, and listens on Transaction.updates —
// no host store code.
let store = auth.storeKitPayments()

// Ask-to-buy approvals and cross-device buys complete outside a direct
// purchase() call; the store verifies and finishes them automatically and
// reports the outcome here (main queue). Optional — leave unset if you
// don't need to observe them.
store.onTransactionUpdate = { outcome in
    if outcome.isVerified { /* grant landed; refresh your entitlements view */ }
}

// Shop rows: catalog product + StoreKit display name/price (or
// isResolvable == false when the store has no such product yet). Render
// these in your own shop UI.
let rows = try await store.loadProducts()

// One-call purchase: StoreKit sheet → JWS proof → verifyTransaction /
// verifyConsumable → Transaction.finish(). Grant from the outcome. Pass the
// catalog row you rendered the Buy button from — the pipeline uses it as-is;
// `purchase(productId:)` is the by-id variant (it refreshes the bootstrap
// snapshot once when the snapshot does not know the id).
let outcome = try await store.purchase(row.product)
if outcome.isVerified {
    // entitlements: [Entitlement] (one_time/subscription) — also published
    // to the entitlement snapshot; receipt: ConsumableReceipt? (consumable).
}
// outcome.isCancelled / outcome.isPending are statuses, not errors.

// Restore works out of the box (the built-in proof source is registered).
let result = try await store.restore()
```

Every method also has an `@objc` completion twin
(`loadProducts(_:)`, `purchase(productId:completion:)`,
`purchase(_:completion:)`, `restore(_:)`), so Objective-C and Unity hosts get
the same feature without a Swift file — StoreKit 2 is a Swift-only API, and
the SDK now owns that side.

The headless surface (`payments()` / `entitlements()`) is unchanged — the
built-in store calls exactly those APIs, and hosts that own their StoreKit
integration (Unity IAP) keep working as before.

## Payments and entitlements (headless)

The headless payments surface is the contract the built-in store (previous
section) is written on, and the path for hosts that own their store client
(Unity IAP, a custom StoreKit bridge). The SDK verifies nothing
locally and grants nothing by itself: your game buys through a store, then
hands the resulting proof to the SDK. Core API re-verifies that proof with
Apple before granting an entitlement, so a client claim is only a hint and
cannot unlock content on its own. On iOS and macOS only `app_store` proofs are
submitted; the Android SDK owns `google_play`.

### Products

The public catalog arrives with `bootstrap()` — reading it makes no network
call. It contains product IDs, platform, type, and entitlement keys; never
prices, credentials, or player data.

```swift
let catalog = auth.payments().products()
guard catalog.enabled else { return }   // shop closed
for product in catalog.forPlatform(PaymentProvider.appStore) {
    print(product.productId, product.type, product.entitlements)
}
let premium = catalog.product("com.example.premium")
```

The catalog fails closed: before bootstrap, when your application has no
store enabled, or when the block is missing/malformed,
`catalog.enabled == false` with an empty list.

### Verify a purchase

Submit the StoreKit 2 `jwsRepresentation` after StoreKit reports a verified
transaction. There is no `verifyReceipt` fallback in the Core API contract.

```swift
do {
    let proof = try TransactionProof.appStore(
        productId: transaction.productID,
        jwsRepresentation: transaction.jwsRepresentation)
    let entitlements = try await auth.payments().verifyTransaction(proof)
} catch {
    // typed SdkError; see Error handling
}
```

The call is bound to the signed-in session's bearer token, so a proof can
never be applied to another player. The JWS is sent once, never logged, and
never persisted; `TransactionProof.description` redacts it.

If there is no session, the SDK signs in as a guest first when your
application allows guest login, so an anonymous purchase works without host
code. With guest login disabled the call throws
`client.auth.not_authenticated`.

Ownership is single-owner and only moves away from an anonymous guest: if the
purchase is already bound to a player with no email or social identity, a
store-verified proof here transfers it to the current player and the previous
owner loses it. Once the owner has an email or social identity the purchase is
sticky: this call throws `SdkConflictError` (`140006`,
`client.payment.owned_by_another_account`) and changes nothing, so ask the
player to sign in as the owning account.

### Restore and read entitlements

Restore is what the app calls at startup and behind a "Restore purchases"
button. It recovers a purchase in both lifecycle cases: a restart with the
stored session recomputes the same player's rows, and a reinstall starts as a
fresh guest whose anonymous binding is moved by a store-verified proof. To
cover the second case without collecting proofs at every call site, register a
proof source once:

```swift
final class StoreProofs: PaymentProofSource {
    func collectProofs(_ completion: @escaping ([TransactionProof], Error?) -> Void) {
        Task {
            var proofs: [TransactionProof] = []
            for await entry in Transaction.currentEntitlements {
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
```

The source runs off your thread within a 10 s bound and the SDK submits at
most 20 proofs; extras and `nil` entries are dropped. A source error, timeout,
or throw never fails the restore: the ledger is still recomputed and
`result.proofsUnavailable` is `true`, so show a retry instead of hiding a paid
feature.

```swift
// Ledger recompute plus the proofs the registered source collected.
let result = try await auth.payments().restore()
print(result.entitlements.count, result.verified, result.rejected,
      result.conflict, result.proofsUnavailable)

// Optional explicit proofs (max 20 per call) — always win over the source.
// An invalid proof counts as `rejected`; it does not fail the restore. A
// proof that resolves to another anonymous player's binding transfers it to
// the current player, while a proof owned by a credentialed account counts
// as `conflict` (result.hasConflict) and changes nothing.
let repaired = try await auth.payments().restore(proofs: [proof])

// Re-read the current rows at any time (ledger only, no store call).
let snapshot = try await auth.entitlements().refresh()
let unlocked = auth.entitlements().has("premium")   // active or grace only
let history = auth.entitlements().list()            // includes expired/revoked
let unsubscribe = auth.entitlements().onChanged { snapshot in
    // fires on verify, restore, refresh, sign-in, and sign-out
}
```

Entitlement states are `active`, `grace`, `expired`, and `revoked`. Only
`active` and `grace` are usable; expired and revoked rows stay in `list()`
so you can show history. `expiresAt` is `nil` for non-expiring one-time
grants. The device stores the session and never the grants: the in-memory
snapshot is `nil` on a cold start until the first read and is cleared whenever
the signed-in player changes or signs out, so one player's grants never leak
into another session. Treat a missing snapshot as **unknown**, not as "not
purchased".

Payment calls keep their own token fresh: `verifyTransaction`,
`restore`, and `entitlements().refresh()` rotate a stale access token
through `ensureSession` first, so a session older than the 900 s token
lifetime (a store sheet left open, an idle game) still works instead of
throwing `auth.token.invalid`.

Every method also has an Objective-C completion-handler twin
(`verifyTransaction(_:completion:)`, `restore(_:)`,
`restore(proofs:completion:)`, `refresh(_:)`), and `PaymentProofSource` is an
`@objc` protocol so an Objective-C host can implement the proof source too —
see [Payments in Objective-C](#payments-in-objective-c) for the full ObjC
walkthrough.

### Consumables

Both stores sell consumables now. The catalog parses a `consumable` row
(`isConsumable`, empty `entitlements`) — a consumable that names an
entitlement is still rejected. `verifyConsumable` with an
`TransactionProof.appStore(productId:jwsRepresentation:)` runs the full App
Store delivery: the server re-verifies the JWS, records the delivery on the
Open4ID ledger (Apple has no server-side consume, so "consumed" lives on the
ledger and the receipt's `already_delivered` state keeps a re-verified JWS
from re-delivering), and answers a `ConsumableReceipt`. The game grants items
keyed by `receipt.transactionRef` and grants nothing unless the state is
`delivered` or `already_delivered`; `pending` means retry the verify, and
`refunded` means the purchase was reversed. `verifyTransaction` still works
for entitlement products and skips the entitlement publish whenever the
response carries a `delivery` block, so a consumable payload cannot clear the
cached snapshot.

## Payments in Objective-C

The whole payments surface is callable from Objective-C — same classes,
same behavior, `@objc` completion-handler twins instead of `async`/`throws`.
This section mirrors [Payments and entitlements](#payments-and-entitlements-headless)
in ObjC; the verification rules, guest sign-in, and ownership semantics are
identical and are not repeated here.

### Import and namespaces

```objc
#import <Open4IDSDK/Open4IDSDK-Swift.h>

// Get the namespaces once; the objects are stable for the client's lifetime.
Open4IDPayments *payments = auth.payments;
Open4IDEntitlements *entitlements = auth.entitlements;
```

Import notes:

- The direct-header import (`Open4IDSDK-Swift.h`) is the form that works in
  every consumption path: the XCFramework ships it in every slice
  (`Headers/Open4IDSDK-Swift.h`), and an SPM build exposes it on the header
  search path. `@import Open4IDSDK;` compiles only in some SPM setups (a
  pure-Objective-C target consuming a source package); a mixed ObjC/Swift
  target fails to find the module, so prefer the header import.
- The XCFramework ships static libraries plus the generated header — there
  is no Clang module, so `@import` cannot resolve against it.
- `PaymentProvider` (the `google_play` / `app_store` string constants) is a
  Swift-only namespace; from ObjC pass the plain strings `@"app_store"` /
  `@"google_play"`.

### Catalog, proofs, and verify

```objc
// Catalog snapshot from bootstrap — no network call.
PaymentCatalog *catalog = [payments products];
if (catalog.enabled) {
    for (PaymentProduct *product in [catalog forPlatform:@"app_store"]) {
        NSLog(@"%@ [%@] entitlements=%@", product.productId, product.type,
              product.entitlements);
    }
}
PaymentProduct *premium = [catalog product:@"com.example.premium"];

// Build a proof from the StoreKit 2 JWS (see the StoreKit note below).
NSError *proofError = nil;
TransactionProof *proof = [TransactionProof
    appStoreWithProductId:transaction.productID
      jwsRepresentation:jws error:&proofError];

// One-time / subscription: grants entitlements.
[payments verifyTransaction:proof completion:^(NSArray<Entitlement *> * _Nullable granted,
                                               NSError * _Nullable error) {
    if (error) { /* NSError, domain Open4IDSDK */ return; }
    for (Entitlement *entitlement in granted) {
        NSLog(@"%@ [%@]", entitlement.key, entitlement.state);
    }
}];

// Consumable: grants nothing; act on the delivery receipt.
[payments verifyConsumable:proof completion:^(ConsumableReceipt * _Nullable receipt,
                                              NSError * _Nullable error) {
    if (error) { return; }
    if (receipt.isDelivered) {
        // Grant receipt.quantity items keyed by receipt.transactionRef.
    } else if (receipt.isAlreadyDelivered) {
        // Replay — do not grant again.
    }
    // isPending → retry the verify; isRefunded → purchase reversed.
}];
```

`RestoreResult` fields read the same from ObjC (`verified`, `rejected`,
`conflict`, `proofsUnavailable`, `hasConflict`), as do the entitlement row
fields (`key`, `state`, `source`, `productId`, `type`, `grantedAt`,
`expiresAt`, `isUsable`). Explicit-proofs restore uses
`restoreWithProofs:completion:` (max 20 proofs per call).

### Restore and entitlement reads

```objc
// Register the proof source once (protocol is @objc — implement it in ObjC).
payments.proofSource = myProofSource;

[payments restore:^(RestoreResult * _Nullable result, NSError * _Nullable error) {
    if (error) { return; }
    NSLog(@"verified=%ld rejected=%ld conflict=%ld noProofs=%d",
          (long)result.verified, (long)result.rejected, (long)result.conflict,
          result.proofsUnavailable);
}];

// Ledger-only reads.
[entitlements refresh:^(EntitlementSnapshot * _Nullable snapshot,
                        NSError * _Nullable error) { /* … */ }];
BOOL unlocked = [entitlements has:@"premium"];   // active or grace only
NSArray<Entitlement *> *history = [entitlements list];
void (^unsubscribe)(void) = [entitlements onChanged:^(EntitlementSnapshot * _Nullable snapshot) {
    // fires on verify, restore, refresh, sign-in, and sign-out
}];
```

### StoreKit 2 is Swift-only — plan for one small bridge file

The `PaymentProofSource` protocol and every verify call are ObjC, but the
proof itself — the StoreKit 2 `jwsRepresentation` — comes from a Swift-only
API: the StoreKit framework's ObjC headers expose only the legacy `SK*`
types, and none of them carries the JWS (there is no `verifyReceipt`
fallback). A pure-ObjC store client therefore cannot produce a usable proof.
Two ways out, both Apple-supported:

- Your project already has Swift in it (or uses Unity IAP) —
  hand the `jwsRepresentation` string over the existing bridge and pass it to
  `[TransactionProof appStoreWithProductId:jwsRepresentation:error:]`; or
- keep one small Swift file that wraps StoreKit 2 behind `@objcMembers`
  types, exactly what the sample
  [`examples/macos-sdk-minimal-objc`](../../examples/macos-sdk-minimal-objc)
  does (`StoreKitBridge.swift`) while the UI, configuration, and every SDK
  call stay in ObjC.

Threading: the completion twins may fire on a background executor, so hop to
the main queue (`dispatch_async(dispatch_get_main_queue(), …)`) before
touching UIKit/AppKit in a completion body. `collectProofs:` may call its
completion on any thread — the SDK bounds the wait at 10 s and submits at
most 20 proofs.

## Error handling

The SDK exposes a typed error hierarchy with **stable keys and integer
codes**. Never branch on the message text — strings are human-readable and
can change between minor versions:

| Swift type | Code | Meaning |
|------------|------|---------|
| `SdkValidationError` | `100003` | Client validation failure; `fieldErrors` maps unsafe fields (e.g. `appId`, `redirectUri`). |
| `SdkAuthError` | `110003` | Invalid key/credentials (`110005`), email verification required (`120001`), token failures. |
| `SdkNotFoundError` | `130004` | Unknown payment transaction or entitlement. |
| `SdkConflictError` | `140006` | Purchase bound to another credentialed account (`client.payment.owned_by_another_account`); restore reports it as `conflict` instead. |
| `SdkRateLimitedError` | `150001` | Rate limit; carries `retryAfterSec` (-1 when the server did not specify). |
| `SdkUnavailableError` | `160001` | Core API or transport unavailable (timeout, HTTP 5xx, connectivity). |
| `SdkStoreUnavailableError` | `160003` | Store verification temporarily unavailable; retryable. Subclasses `SdkUnavailableError`. A `503` on **every** verify is not transient — on the App Store path it has two per-node causes: the Portal's Payments → App Store section not saved for the `(app, environment)` the client asserts (`bundle_id` empty or `notification_environment` invalid; a disabled provider or unknown product answers `400 invalid` instead), or the node missing its pinned Apple root (`priv/payment/apple_root_ca_g3.pem` must ship with the release — a missing/mismatched file answers 503 before the JWS is read; if another node sharing the database verifies fine, it is this one). The Vault key is not used by verification. |
| `SdkInternalError` | `170001` | Unexpected internal failure. |
| `SdkNotImplementedError` | `-1` | Method awaiting its implementation phase (rare; only ahead of a shipped feature). |

Stable error keys mirror the sibling SDKs, e.g. `client.auth.not_authenticated`,
`client.auth.invalid_request`, `client.auth.provider_unavailable`,
`client.auth.popup_closed`, `client.auth.popup_timeout`,
`client.auth.popup_blocked`, `client.auth.access_denied`, `system.*`, `sdk.*`
(e.g. `sdk.not_initialized`).

As `NSError`, the domain is `Open4IDSDK`, the code is the integer error code,
and `userInfo` carries `key`, `error_code` (and, when applicable,
`field_errors`, `retry_after_sec`).

## Token storage

| Backend | Default | Notes |
|---------|---------|-------|
| `MemorySessionStore` | yes | In-memory only; session is lost when the process dies. |
| `KeychainSessionStore` | opt-in | Generic-password item per `service`/`account`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. |

The Keychain adapter is best-effort: I/O failures never break sign-in (the
last `OSStatus` is exposed on `lastStatus` for diagnostics), and corrupt or
foreign payloads degrade to "nothing stored" rather than crashing.

Tokens are never written to `UserDefaults` and never logged — every
description of a session or configuration redacts token values, and the SDK
key is always truncated to its last four characters.

Pass the store at `configure`; switch the backend at runtime with
`setSessionStore(_:)` (`nil` restores in-memory only).

## Security model

- **No secrets in the SDK.** `sdk_sk_...`, OAuth client secrets, Apple
  private keys, and Vault references never enter the iOS client. The
  `sdk_pk_...` key is public by design.
- **No local JWT validation.** Player tokens are opaque and are validated
  server-side. The SDK never parses a JWT nor exchanges JWKS material.
- **Exact-match redirect URIs.** Native redirect URIs are custom schemes
  registered per app (`com.example.game://open4id/callback`). The Portal
  bridges only open the exact registered scheme and bundle id.
- **No WebView authentication.** All hosted flows use
  `ASWebAuthenticationSession`, never a `WKWebView` you own.

## Objective-C and Unity notes

- The XCFramework's generated header (`Open4IDSDK-Swift.h`) exposes all
  public model types — `AuthSession`, `UserInfo`, `Bootstrap`,
  `AuthDiscovery`, `ProviderRef`, `LoginReadiness`, `ServerCallback`,
  `ServerCallbackReceipt`, `SessionSnapshot`, and the payments set
  (`PaymentCatalog`, `PaymentProduct`, `TransactionProof`, `Entitlement`,
  `EntitlementSnapshot`, `RestoreResult`, `ConsumableReceipt`) — with
  properties readable from Objective-C.
- Import the generated header directly
  (`#import <Open4IDSDK/Open4IDSDK-Swift.h>`); it is the one form that works
  for both the SPM package and the XCFramework. The XCFramework ships no
  Clang module, and `@import Open4IDSDK;` resolves only in some SPM setups
  (pure Objective-C targets with a source package).
- `RedactedConfig` (the return of `getConfig()`) is a nested Swift type and
  is not exposed to Objective-C; simply check `getConfig() != nil` to
  confirm configuration success.
- The SwiftUI UI layer is not reachable from Objective-C directly; use the
  `Open4IDLoginDialogObjC` facade as shown in
  [Login dialog](#login-dialog-built-in-ui).
- Auth flows end to end from a pure ObjC app: `examples/ios-sdk-minimal-objc`
  (UIKit). Payments end to end on macOS with ObjC UI and SDK calls:
  `examples/macos-sdk-minimal-objc` (AppKit; keeps one Swift file for the
  Swift-only StoreKit 2 JWS bridge — see
  [Payments in Objective-C](#payments-in-objective-c)).
- For Unity/Unreal, write a thin ObjC/ObjC++ shim against the
  `Open4IDSDK.xcframework` surface and expose it to the engine through your
  normal bridge (the same pattern used by other Swift game SDKs); in-engine
  bindings are shipped externally, see the support channel for details.

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|-------------------|
| `SdkValidationError` with `fieldErrors["appId"]` or `["publicSdkKey"]` | Values do not match the `app_…` / `sdk_pk_…` shapes — check for copy-paste truncation. |
| `SdkValidationError` with `fieldErrors["redirectUri"]` | The redirect URI is not exact-registered or misses a custom scheme; compare with the value in the Open4ID console (character-for-character). |
| `sdk.not_initialized` | `configure` did not complete successfully (or was never called) before another method ran. |
| `client.auth.not_authenticated` | The session expired or was cleared externally; use `ensureSession(minValidityMs:)` before gameplay. |
| `client.auth.popup_timeout` from Apple/GitHub/Facebook | The custom scheme is not registered in URL Types, or the sign-in browser was dismissed/blocked; re-register the scheme and call again. |
| `client.auth.provider_unavailable` when calling Google on iOS | Expected — implement/override `getGoogleAuthorizationCode` or register a provider (see [Social providers](#social-providers)). |
| `SdkRateLimitedError` (`150001`) | Rate limit hit; honor `retryAfterSec` before retrying the same request. |
| Keychain item missing after relaunch | No store passed at configure time — pass `KeychainSessionStore(...)`; also check `lastStatus`. |
| Session lost on short backgrounding | On iOS, OS may kill the process in background. Ensure a persistent store to survive process death. |
