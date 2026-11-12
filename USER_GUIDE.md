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
5. [One-call startup](#one-call-startup)
6. [Events and subscription state](#events-and-subscription-state)
7. [Sign players in](#sign-players-in)
8. [Login dialog (built-in UI)](#login-dialog-built-in-ui)
9. [Social providers](#social-providers)
10. [Session management](#session-management)
11. [Player account flows](#player-account-flows)
12. [Delegate verification to your server (server callback)](#delegate-verification-to-your-server-server-callback)
13. [Payments the easy way (built-in store)](#payments-the-easy-way-built-in-store)
14. [Payments and entitlements (headless)](#payments-and-entitlements-headless)
15. [Payments in Objective-C](#payments-in-objective-c)
16. [Error handling](#error-handling)
17. [Token storage](#token-storage)
18. [Security model](#security-model)
19. [Objective-C and Unity notes](#objective-c-and-unity-notes)
20. [Troubleshooting](#troubleshooting)

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

Each slice ships a Clang module map at `Headers/module.modulemap` (the
location Xcode reads for a library XCFramework) and at
`Modules/module.modulemap`. With the framework added to your target, a pure
Objective-C or Objective-C++ file can therefore write `@import Open4IDSDK;`
with no `FRAMEWORK_SEARCH_PATHS`, `HEADER_SEARCH_PATHS`,
`-fmodule-map-file`, or header symlink. The direct header import
(`#import <Open4IDSDK/Open4IDSDK-Swift.h>`) also works when you add the
slice's `Headers` directory to the search path. For an **Objective-C++**
host, keep `-fcxx-modules` on the files that import it — the generated Swift
header contains `@import AuthenticationServices;`, and clang rejects
`@import` inside C++ unless modules are enabled for C++ too.

> Artifacts **before 0.8.8** ship no Clang module (0.7.0's zip predates
> this change), so ObjC hosts on them must import the header directly or use
> the `Open4IDSDKModule` adapter from the examples. Upgrade to 0.8.8 to
> drop both workarounds.

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

## One-call startup

`start()` runs the startup order the SDK expects, so hosts stop
reimplementing it:

1. creates the built-in StoreKit adapter unless you already registered
   `payments().proofSource` yourself, so the launch restore can submit
   store proofs;
2. calls `bootstrap()` (auth discovery + payments catalog);
3. waits for the launch restore that bootstrap scheduled, so paid state is
   settled and a stored player keeps their session;
4. signs in as a **guest** only when nothing was restored and the
   application allows guest login.

```swift
auth.start { session, error in
    if let error {
        // Offline first launch: cached paid state is still readable
        // (`auth.entitlements().current()`), and `start()` can be retried.
        return
    }
    guard let session else { return }
    switch auth.sessionState {
    case .guest:         showGame(session)
    case .authenticated: showGame(session)
    case .expired:       showGame(session)   // rotation is automatic
    case .none:          showSignIn()
    }
}
```

Or with async/await:

```swift
let session = try await auth.start()
// start() returns a session: guest, authenticated, or expired (an expired
// token is rotated on the next SDK call).
startGame(session)
```

```objc
[auth start:^(AuthSession * _Nullable session, NSError * _Nullable error) {
    if (error) { return; }   // retry later; cached paid state survives
    switch (auth.sessionState) {
        case Open4IDSessionStateGuest:
        case Open4IDSessionStateAuthenticated:
        case Open4IDSessionStateExpired:   // a session exists; do not mint a guest
            [self showGame:session];
            break;
        case Open4IDSessionStateNone:
            [self showSignIn];
            break;
    }
}];
```

`start()` is thread-safe and single-flight: concurrent calls share one
sequence. A failed call can simply be called again — no cleanup is required —
and a stored session is **never** replaced by a guest.

Branch on `sessionState`, not `isAuthenticated()`:

| `sessionState` | Meaning | What the host does |
| --- | --- | --- |
| `.none` | No session: nothing restored, no guest signed in | Show sign-in / onboarding |
| `.guest` | Anonymous guest session | Start the game; offer `linkEmail` later |
| `.authenticated` | Email/password, Google, GitHub, or Apple session | Start the game |
| `.expired` | A session exists but its access token aged out | Start the game anyway — the SDK rotates the token on the next call. **Do not** sign in a new guest |

`isAuthenticated()` answers "is the **access token** valid right now", which
is why it is the wrong test for "is the player signed in". Use
`hasStoredSession()` to know whether a previous process persisted a session
for this app/environment (the Keychain default survives a reinstall).

If you prefer to control the order yourself, `bootstrap()`,
`continueAsGuest()`, and the built-in store still work as before; see
[Sign players in](#sign-players-in) and
[Payments the easy way](#payments-the-easy-way-built-in-store).

## Events and subscription state

Hosts used to forward SDK state into their own bus — a notification per
listener, plus per-product-id checks over `isPurchased` for the settings
screen. `onEvent` collapses that into one block, and
`subscriptionState(productId:)` answers paid state directly.

### One event block

```swift
auth.onEvent = { event in
    switch event.kind {
    case .auth:
        // event.success (a session exists), event.message == "guest"/"google"/…
        self.renderAccount(event.success)
    case .products:
        // catalog rows arrived (message "catalog:8") or StoreKit resolved them
        // (message "store:8"). Rebuild the shop here instead of after bootstrap.
        self.renderShop()
    case .entitlements:
        // event.entitlements is the new snapshot; success:false with an empty
        // list means it was cleared (sign-out, reset, player switch).
        self.refreshOwnedBadges(event.entitlements)
    case .purchase:
        // event.productId + event.message ("verified", a consumable state, or
        // a stable error key). Grant from entitlements/current() as usual.
        self.showPurchaseResult(event.success, event.productId)
    case .restore:
        // event.message == "verified=2 rejected=0 conflict=0"; event.entitlements
        // is the recomputed snapshot. Hide the "Restore" spinner here.
        self.finishRestore(event)
    case .transaction:
        // Ask-to-buy approval or a cross-device buy finished in the background.
        self.grantDeliveredItems(event.entitlements)
    @unknown default:
        break
    }
}
```

```objc
auth.onEvent = ^(Open4IDEvent *event) {
    switch (event.kind) {
        case Open4IDEventKindAuth:         [self renderAccount:event.success]; break;
        case Open4IDEventKindProducts:     [self renderShop]; break;
        case Open4IDEventKindEntitlements: [self refreshOwnedBadges:event.entitlements]; break;
        case Open4IDEventKindPurchase:     break;
        case Open4IDEventKindRestore:      break;
        case Open4IDEventKindTransaction:  break;
        default: break;
    }
};
```

Rules that matter:

- **Additive.** `onAuthStateChanged`, `entitlements().onChanged`, and
  `storeKitPayments().onTransactionUpdate` keep firing. Migrate one path at
  a time; `onEvent` is sugar, not a replacement you must adopt at once.
- **Delivered on the callback queue** (see
  [Callback queue](#callback-queue)) — main by default, `nil` for
  synchronous delivery. State is settled when the block runs, so reading
  `entitlements().current()` inside it is safe.
- **`message` is safe to log.** It is a stable error key
  (`client.payment.rate_limited`) or a short summary, never a token or a
  store proof. `productId`/`message` are `nil` and `entitlements` empty
  when a kind does not carry them.
- **Set it before `configure`** if you want the first bootstrap and sign-in
  events; setting `nil` detaches it.

### Subscription state

```swift
let state = auth.subscriptionState(productId: "com.example.premium")
// or: auth.entitlements().subscriptionState(productId: …)
```

| State | Meaning | UI |
| --- | --- | --- |
| `.active` | A usable `active` row exists | Show as subscribed |
| `.grace` | The store is retrying billing; the server still grants access | Show as subscribed, optionally "payment problem" |
| `.expired` | The row is past its expiry, or its state is `expired` | Show renewal |
| `.none` | Revoked-only, or no row while the snapshot is known | Show the buy button |
| `.unknown` | No snapshot yet, product in neither catalog, or a consumable | Show **checking**, never "locked" |

The accessor reads the live catalog first, then the catalog stored with the
paid-state snapshot, so it answers on an offline cold launch. That is why it
beats a `isPurchased(productId:)` boolean: a boolean cannot tell billing
retry from expiry, and it cannot say "not loaded yet". Iterate
`payments().products().products` and call it per row instead of hardcoding
product ids.

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

> **Persisted by default:** `configure` without a `store` falls back to
> the Keychain adapter, so the session — and the guest identity behind it
> — survives relaunches and reinstall cycles (Keychain items outlive the
> app sandbox). The same player keeps the same account, and the launch
> restore finds their grants without store proofs:
>
> ```swift
> // default: KeychainSessionStore() — nothing to pass
> try auth.configure(...)
>
> // opt out (tests, kiosks, multi-tenant shells): memory-only, sticky
> auth.setSessionStore(nil)            // or setSessionStoreMemoryOnly() from Objective-C
>
> // or namespace one process that embeds several Open4ID applications
> try auth.configure(..., store: KeychainSessionStore(service: "com.game.app1"))
> ```
>
> The adapter stores one generic-password Keychain item per `service`/
> `account` pair; pass `account:` to namespace sessions when one process
> embeds more than one client.

### Objective-C

Every `async` Swift API ships a completion-handler twin callable from
Objective-C. Import the SDK with `@import Open4IDSDK;` (0.8.8+ XCFramework,
no build settings needed) or with the generated header
(`#import <Open4IDSDK/Open4IDSDK-Swift.h>`), which works in every
consumption path. `@import` in an SPM source-package target depends on the
target being pure Objective-C.
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

// Session persistence works from Objective-C too — `SessionStore` is an
// @objc protocol and `KeychainSessionStore` is the shipped default:
[auth setSessionStore:[[KeychainSessionStore alloc] init]];                       // default shape
[auth setSessionStore:[[KeychainSessionStore alloc]
                              initWithService:@"com.game.open4id"
                                      account:@"app_9f3ab2c1"]];                // namespaced
// Or implement `Open4IDSessionStore` yourself (load/save/clear over
// your own storage). Memory-only opt-out: [auth setSessionStoreMemoryOnly];

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
yourself yet. Availability is split in two: `login.guest_enabled` is the
server capability (guest identities may exist, and payments may bind to one),
while `login.guest_button_visible` only decides whether the built-in views
render "Continue as guest". The Core API defaults the button to the
capability when the flag is absent, so older configurations behave exactly as
before. Anonymous checkout is `guest_enabled = true` with
`guest_button_visible = false`; login-required applications set both `false`.

Two flavors ship in the package:

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

### Callback queue

Every SDK listener — entitlement changes, purchase outcomes, auth-state
changes, and server-callback errors — fires on the queue you choose with
`setCallbackQueue(_:)`. The default is the **main queue**, so a UIKit or
AppKit host updates views directly inside the callback:

```swift
auth.setCallbackQueue(.main)                    // default; explicit is fine
auth.entitlements().onChanged { snapshot in
    // main thread: safe to touch views
    self.render(snapshot)
}
```

```objc
[auth setCallbackQueue:dispatch_get_main_queue()];   // default
```

Pass `nil` to deliver synchronously on the publishing thread — useful for
headless servers and tests that assert immediately after a call:

```swift
auth.setCallbackQueue(nil)
```

Delivery is asynchronous on a non-`nil` queue, but **state is already
settled** when your callback runs: `entitlements().current()`,
`getSession()`, and `sessionState` reflect the new state, so a listener never
races the SDK. A serial queue (the main queue included) delivers listener
invocations in order, so do not block it with synchronous network or long
file I/O.

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

`purchase` preflights **before** opening the StoreKit sheet: with no session
and guest login disabled it throws `client.auth.not_authenticated` instead of
charging a player whose verify would be rejected. Gate your Buy buttons on
`auth.canPurchase()` / `auth.requiresSignIn()`: both are fail-closed before
the first bootstrap (`canPurchase()` is `false`), and `requiresSignIn()` is
`true` only once bootstrap confirms guest login is off and there is no
session. The guest identity itself is still minted after the player confirms
the sheet, not at preflight time.

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

The SDK restores on its own: once per process, after the first `bootstrap()`
that advertises a payments catalog, it rehydrates paid state — a stored
session refreshes its ledger rows and, when a proof source is registered
(the built-in store registers one), also submits the store's current
receipts, so renewals recorded only by the store and purchases made before
persistence existed repair themselves at launch; a missing session signs in
as a guest (when guest login is enabled) and restores through the
registered proof source. The result lands in the same snapshot and
`onChanged` fires, so a purchase made in a previous run is usable again
right after a restart or a reinstall, with no host code. Set
`auth.payments().autoRestoreOnLaunch = false` before the first `bootstrap()`
if you want paid state to be strictly host-driven.

You can still restore explicitly behind a "Restore purchases" button — the
same call the SDK schedules at launch: it recovers a purchase in both
lifecycle cases (a restart with the stored session recomputes the same
player's rows, and a reinstall starts as a fresh guest whose anonymous
binding is moved by a store-verified proof — the previous owner's derived
rows are dropped in the same operation). To cover the second case
without collecting proofs at every call site, register a proof source once:

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

The source runs off your thread within a 10 s bound; the SDK chunks every
collected proof into requests of at most 20 proofs and 48 KiB, so nothing is
dropped. A source error, timeout, or throw never fails the restore: the ledger
is still recomputed and `result.proofsUnavailable` is `true`, so show a retry
instead of hiding a paid feature.

```swift
// Ledger recompute plus the proofs the registered source collected.
let result = try await auth.payments().restore()
print(result.entitlements.count, result.verified, result.rejected,
      result.conflict, result.proofsUnavailable)

// Optional explicit proofs (any count; the SDK chunks them) — always win over
// the source. An invalid proof counts as `rejected`; it does not fail the
// restore. A proof that resolves to another anonymous player's binding
// transfers it to the current player, while a proof owned by a credentialed
// account counts as `conflict` (result.hasConflict) and changes nothing.
let repaired = try await auth.payments().restore(proofs: [proof])

// Re-read the current rows at any time (ledger only, no store call).
let snapshot = try await auth.entitlements().refresh()
let unlocked = auth.entitlements().has("premium")   // active or grace only
let history = auth.entitlements().list()            // includes expired/revoked
let unsubscribe = auth.entitlements().onChanged { snapshot in
    // fires on verify, restore, refresh, sign-in, and sign-out
}
```

**What restore cannot recover.** A proof only exists for purchases the
store still reports, and only moves bindings owned by an anonymous guest.
A reinstall with a lost session therefore recovers every non-consumable
purchase and subscription, but not:

- **Finished consumables** — Apple removes them from
  `currentEntitlements` once finished, and their delivery record stays
  bound to the previous guest. This is why the session persists in the
  Keychain by default (0.7.0): with the session intact the same player
  keeps consumable delivery history. Game-side, re-deliver consumables
  from your persisted `transactionRef` records, never from a live query.
- **A purchase whose owner upgraded to an email/social account** — counted
  as `conflict`; ask the player to sign in as the owning account.
- **Purchases the device's store account no longer reports** (different
  Apple ID signed in, refunded, or removed) — `proofsUnavailable` /
  `rejected`.
- **Offline** — StoreKit's collection is local, but verification and the
  ledger are server-side; restore needs connectivity and is the moment to
  gate features as "checking" rather than "locked" (see the offline
  cold-start pattern under *Entitlement states* below).

Entitlement states are `active`, `grace`, `expired`, and `revoked`. Only
`active` and `grace` are usable; expired and revoked rows stay in `list()`
so you can show history. Usability is time-aware: `has`/`isUsable` treat a
cached `active` row whose `expiresAt` has passed as unusable even before
the next refresh recomputes it (parse dates yourself with
`expiresAtDate`/`remainingSeconds` when you need to display time left).
`grace` is exempt — Core API keeps a grace row's `expiresAt` at the
original period end while the store's billing-retry window runs, and the
grace-window end is the server's decision (it arrives as the next state on
a later read). `expiresAt` is `nil` for non-expiring one-time
grants. The device stores the session and, since 0.8.0, the last known paid
state (the entitlement rows plus the catalog they were resolved against):
the rows are re-fetched from the ledger by the SDK, and the cached copy is
replayed on a cold start so the game can render before the network answers.
`configure` hydrates that cache, so `current()` is already readable offline
right after configuration — flagged `isFromCache == true` with `savedAt` set
to the fetch time. The first `refresh()`/`restore()`/verify replaces it with
live rows, and it is cleared whenever the signed-in player changes or signs
out, so one player's grants never leak into another session. Treat cached
rows as **last known** paid state (they still go through the time-aware
`isUsable` check) and a missing snapshot as **unknown**, never as "not
purchased"; drive UI from `onChanged` rather than a one-time read.

**Offline cold starts and the three-state check.** The launch restore is
best-effort: offline it fails silently, but the hydrated cache keeps
`current()` readable, so the shop is not blank. When no cache exists yet
(a first launch, or a player who never had a successful read), the snapshot
is `nil`. Gate features on all three states — `has(key)` when known-usable,
"checking/try online" when the snapshot is `nil`, locked only when the
snapshot exists and the row is absent, `expired`, or `revoked`. Two
host-side patterns cover an uncached offline start without ever painting
"locked" for an unknown: keep your own last-known-usable-keys cache (keyed
by `userId`, honoring `expiresAt` for subscriptions; OR it in only while the
snapshot is `nil`), and/or fall back to StoreKit's
`Transaction.currentEntitlements`, which StoreKit caches offline. Never
derive "locked" from a `nil` snapshot.

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

## Store timing and environments (sandbox and TestFlight)

Subscription periods in testing do not match wall-clock durations. Before
reporting "the ledger expired my subscription after 5 minutes", check this
table — in almost every case the ledger mirrors the store exactly (the
outcome's `expirationDate` and the entitlement row's `expiresAt` agree):

| Distribution | 1 week | 1 month | 2 months | 3 months | 6 months | 1 year |
| --- | --- | --- | --- | --- | --- | --- |
| Xcode (local StoreKit configuration) | follows the `.storekit` file | | | | | |
| TestFlight (since Dec 2024) | 1 day | 1 day | 1 day | 1 day | 1 day | 1 day |
| Sandbox Apple Account (default) | 3 min | 5 min | 10 min | 15 min | 30 min | 1 hour |

Facts worth knowing before debugging:

- The ledger's `expiresAt` mirrors StoreKit's `expirationDate` — the two
  always agree; a 24-hour expiry is the daily **TestFlight** renewal rate,
  not a stale or incorrect grant.
- **TestFlight** subscriptions renew up to 6 times per week, so a
  subscription can stay `active` for several days.
- The **Sandbox Apple Account** renewal rate is configurable: App Store
  Connect → Users and Access → Sandbox → *Subscription Renewal Rate*.
- Clearing a sandbox account's purchase history does **not** revoke a grant
  the ledger already recorded — sign the test player out of the
  application (or ask support to clear the binding) to test the
  not-purchased path.

### SDK environment vs store environment

Two independent axes; a mismatch is the usual cause of
`client.payment.verification_failed`:

| SDK `environment` (configure + Portal) | Store environment you should test with |
| --- | --- |
| `development` / `sandbox` | `Sandbox` — App Store sandbox account, or `Xcode` with a local `.storekit` configuration |
| `production` | `Production` — App Store live; TestFlight builds also report `Production`-eligible receipts but are typically tested against a `sandbox` configured app |

The pairing is enforced server-side on every verification: a `Production`
receipt never unlocks a `development` application, and the other way
around — no client field can override it. For renewals, expiries, and
refunds to reach the ledger without the app running, configure **App Store
Server Notifications V2** in App Store Connect (the endpoint URL the
Open4ID console shows under Payments → Apple) — the SDK's
`Transaction.updates` listener only covers purchases made on this device
while it runs.

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

- `@import Open4IDSDK;` works with the 0.8.8+ XCFramework: every slice ships
  a Clang module map, so no search paths or flags are needed. The
  direct-header form (`#import <Open4IDSDK/Open4IDSDK-Swift.h>`) also works
  when the slice's `Headers` directory is on the header search path, and is
  the form to use with an SPM **source** package or a pre-0.8.8 artifact.
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
`restoreWithProofs:completion:`; the SDK chunks any number of proofs into
requests of at most 20 and 48 KiB, so a host never splits them.

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
completion on any thread — the SDK bounds the wait at 10 s and chunks the
proofs it gets (20 per request, 48 KiB of serialized JSON).

## Error handling

The SDK exposes a typed error hierarchy with **stable keys and integer
codes**. Never branch on the message text — strings are human-readable and
can change between minor versions:

| Swift type | Code | Meaning |
|------------|------|---------|
| `SdkValidationError` | `100003` | Client validation failure; `fieldErrors` maps unsafe fields (e.g. `appId`, `redirectUri`). |
| `SdkPayloadTooLargeError` | `100005` | `client.payment.request_too_large`: the payment request body exceeded the Core API read limit, or the proof list could not be delivered. Covers both the new `413`/`100005` response and the legacy `400`/`100003` + `field_errors.body = too_large` shape. Restore chunks itself, so this normally never surfaces; if it does, do not retry the same body (`isRetryable == false`). |
| `SdkAuthError` | `110003` | Invalid key/credentials (`110005`), email verification required (`120001`), token failures. |
| `SdkNotFoundError` | `130004` | Unknown payment transaction or entitlement. |
| `SdkConflictError` | `140006` | Purchase bound to another credentialed account (`client.payment.owned_by_another_account`); restore reports it as `conflict` instead. |
| `SdkRateLimitedError` | `150001` | Rate limit; carries `retryAfterSec` (-1 when the server did not specify). |
| `SdkUnavailableError` | `160001` | Core API or transport unavailable (timeout, HTTP 5xx, connectivity). |
| `SdkStoreUnavailableError` | `160003` | Store verification temporarily unavailable; retryable. A `503` on **every** verify is not transient — it means the deployment's App Store configuration is incomplete: check the Portal's Payments → App Store section for the `(app, environment)` the client asserts (`bundle_id` empty or `notification_environment` invalid; a disabled provider or unknown product answers `400 invalid` instead). If the Portal looks right, contact the node operator — it is a server-side deployment issue, not a client or device problem. |
| `SdkInternalError` | `170001` | Unexpected internal failure. |
| `SdkNotImplementedError` | `-1` | Method awaiting its implementation phase (rare; only ahead of a shipped feature). |

`SdkError.isRetryable` answers "can the same call succeed if I repeat it?"
without matching codes: `true` for `150001` (rate limit), `160001` (service
or transport down), and `160003` (store unavailable); `false` for shape
errors (`100001`–`100003`), `100005` (oversize body), auth, conflict,
not-found, and internal errors. The value is also in the bridged
`NSError.userInfo["retryable"]`. Gate automatic retry loops on it.

### Restore outcome matrix

Restore never fails because of one bad purchase. For each submitted proof:

| Server verdict | `RestoreResult` | What the host does |
| --- | --- | --- |
| Store-verified, ledger recorded (or already identical) | `verified` | Nothing; paid state is published through `entitlements.onChanged` |
| Invalid, unknown, or unusable proof (wrong product, malformed JWS, refunded) | `rejected` | Nothing; log through diagnostics if support needs it. The SDK bisects the chunk to isolate it, and the rest still restores |
| Valid proof owned by another **credentialed** account | `conflict` | Ask the player to sign in as that account; nothing was granted |
| Valid proof owned by an **anonymous** guest | `verified` | Nothing; the binding moves to the current player |
| Store unreachable, timeout, or the source threw | `proofsUnavailable == true` | Offer a retry; the ledger rows are still valid |

A total failure (bad token, rate limit, outage) throws instead of returning a
result; a re-run is safe because restore is idempotent.

Stable error keys mirror the sibling SDKs, e.g. `client.auth.not_authenticated`,
`client.auth.invalid_request`, `client.auth.provider_unavailable`,
`client.auth.popup_closed`, `client.auth.popup_timeout`,
`client.auth.popup_blocked`, `client.auth.access_denied`, `system.*`, `sdk.*`
(e.g. `sdk.not_initialized`).

As `NSError`, the domain is `Open4IDSDK`, the code is the integer error code,
and `userInfo` carries `key`, `error_code` (and, when applicable,
`field_errors`, `retry_after_sec`).

## Opt-in diagnostics

The SDK never logs by default. When support needs visibility, opt in once
at launch:

```swift
Open4IDDiagnostics.level = .info
Open4IDDiagnostics.onLog = { line in
    // your logger / console / crash reporter; called on an SDK thread
    print(line)
}
```

`.info` emits redacted lifecycle lines only: the effective configuration
with the SDK key masked to its last four characters, every entitlement
snapshot publish (`key/state/expiresAt/source` per row — the launch
restore, refreshes, restores, and purchases all land here), restore counts
(`verified/rejected/conflict/proofsUnavailable`), store verification
results (product id, kind), and launch-hydration failures as error keys.
Never logged: the JWS, access/refresh tokens, the full SDK key, or any
player credential. From Objective-C the same surface is
`Open4IDDiagnostics.level` / `Open4IDDiagnostics.onLog`.

## Token storage

| Backend | Default | Notes |
|---------|---------|-------|
| `KeychainSessionStore` | yes | Generic-password item per `service`/`account`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; survives relaunches and reinstalls. |
| `MemorySessionStore` | no (opt-out) | In-memory only; session is lost when the process dies. Pass it to `configure(store:)` or `setSessionStore(nil)` for tests, kiosks, or multi-tenant shells. |

The Keychain adapter is best-effort: I/O failures never break sign-in (the
last `OSStatus` is exposed on `lastStatus` for diagnostics), and corrupt or
foreign payloads degrade to "nothing stored" rather than crashing.

Tokens are never written to `UserDefaults` and never logged — every
description of a session or configuration redacts token values, and the SDK
key is always truncated to its last four characters.

Pass the store at `configure`; switch the backend at runtime with
`setSessionStore(_:)` (`nil` restores in-memory only).

### Paid state cache (entitlements + catalog)

The SDK also caches the player's **last known paid state** — the entitlement
rows plus the catalog they were resolved against — and rehydrates it inside
`configure`, before any network call:

```swift
try auth.configure(/* … */)

// Right away, even offline and before the first refresh:
if let snapshot = auth.entitlements().current() {
    print("cached:", snapshot.isFromCache, snapshot.savedAt as Any)
    let premium = auth.entitlements().has("premium")
}
if auth.entitlements().isPurchased(productId: "com.example.premium") {
    unlockPremium()
}
```

- **`isFromCache == true`** means the rows came from the store, not a
  response in this process; `savedAt`/`savedAtMillis` is when they were
  fetched. The next `refresh()`, `restore()`, or verify replaces them with
  live state (`isFromCache == false`) and re-persists.
- Missing paid state is **unknown**, not "not purchased". Cached rows still
  go through the same time-aware expiry (`grace` stays usable; an `active`
  row past its `expiresAt` locks offline).
- The cache is per player and bound to `appId`/`bundleId`: a foreign or
  corrupt item reads as "nothing cached". Sign-out, `reset()`, and a player
  switch clear the departing player's cache only.
- The default backend is `KeychainSnapshotStore` (same trust boundary as
  the session store, survives reinstalls). When the session store is
  `MemorySessionStore`, paid state is memory-only too. Opt out explicitly
  with `setSnapshotStore(nil)`, or pass your own `@objc SnapshotStore`
  adapter (for example a `KeychainSnapshotStore` with distinct
  `service`/`account` values to namespace several applications in one
  process).

```swift
auth.setSnapshotStore(KeychainSnapshotStore(service: "com.game.open4id",
                                            account: "app_9f3ab2c1"))
// or, from Swift:
auth.setSnapshotStore(MemorySnapshotStore())   // or setSnapshotStore(nil)
```

```objc
[auth setSnapshotStore:[[KeychainSnapshotStore alloc]
                        initWithService:@"com.game.open4id"
                                account:@"app_9f3ab2c1"]];
// Paid-state memory-only opt-out:
[auth setSnapshotStoreMemoryOnly];
```

Never cached: tokens, store proofs (JWS), or anything the server owns as an
authoritative grant.

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
  `ServerCallbackReceipt`, `SessionSnapshot`, `Open4IDSessionState`, and the
  payments set (`PaymentCatalog`, `PaymentProduct`, `TransactionProof`,
  `Entitlement`, `EntitlementSnapshot`, `PaymentSnapshot`,
  `RestoreResult`, `ConsumableReceipt`) — with
  properties readable from Objective-C. `SessionStore`/`SnapshotStore` and
  the Keychain/memory adapters are `@objc` too, so a pure ObjC host
  implements persistence without a Swift shim.
- Import with `@import Open4IDSDK;` (0.8.8+ XCFramework ships a Clang module
  map in every slice) or with the generated header directly
  (`#import <Open4IDSDK/Open4IDSDK-Swift.h>`); the header form covers the
  SPM source package and pre-0.8.8 artifacts.
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
| Keychain item missing after relaunch | The Keychain adapter is the default; if the session is still missing, check `lastStatus` on the store and that the item was not wiped by a device reset or a shared `service`/`account` collision. |
| Session lost on short backgrounding | On iOS, OS may kill the process in background. The default Keychain store restores the session on relaunch; if you opted out to memory-only, reconfigure with the Keychain adapter. |
| Paid state missing after relaunch | The launch restore rehydrates grants once per process after the first bootstrap (catalog enabled). If it is still missing: check that `storeKitPayments()` (or a proof source) is set up before the bootstrap so store proofs are available, that guest login is enabled or a session is stored (the default Keychain adapter covers both), and that `autoRestoreOnLaunch` was not set to `false`. Watch `entitlements().onChanged` instead of a one-time `has()` read. |
| Subscription still active after 5 minutes | Expected in testing: a sandbox 1-month subscription lasts 5 minutes, but a **TestFlight** 1-month subscription lasts 24 hours and renews up to 6 times per week — the ledger's `expiresAt` mirrors StoreKit's `expirationDate` exactly. See [Store timing and environments](#store-timing-and-environments-sandbox-and-testflight). |
| Restore after reinstall recovered nothing | Check in order: the device's App Store account is the purchasing one (`StoreKit` reports `currentEntitlements`); the products are non-consumables or subscriptions (finished **consumables** never re-appear — they need the Keychain-persisted session from 0.7.0); the previous owner never upgraded to an email/social account (`conflict` otherwise); and the device is online (verification is server-side). `result.proofsUnavailable == true` means no proof was collected at all. |
| Same player became a different guest after reinstall | The default Keychain session survives reinstalls; a changed guest identity means something cleared the item (device reset, custom `service`/`account`) or persistence was opted out. Purchases recover through the launch restore's store proofs for non-consumables and subscriptions; consumables need the session to survive. |
