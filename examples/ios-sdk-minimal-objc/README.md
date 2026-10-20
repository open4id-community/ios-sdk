# Open4ID iOS SDK Minimal Example (Objective-C)

Pure Objective-C port of `examples/ios-sdk-minimal/`. Demonstrates consuming
the `Open4IDSDK` XCFramework from a **pure ObjC iOS app** — no Swift, no
SwiftUI. Uses `UIKit` and the SDK's `@objc` completion-handler surface.

## What it shows

- `configure` with validation errors returned as `NSError`
- `bootstrap` against the live Core API node
- Guest sign-in, email/password sign-in, register, forgot-password
- GitHub and Apple sign-in via `ASWebAuthenticationSession` (SDK-owned web flows)
- Google sign-in via `Open4IDSocialClient` (Google Sign-In SDK override)
- Login dialog (SDK phase 13) presented from ObjC via `Open4IDLoginDialogObjC`
- Session refresh, sign-out, delete account
- Auth-state listener (`onAuthStateChanged`) firing on sign-in/sign-out
- Auto configure + bootstrap on launch

## Files

| File | Purpose |
|------|---------|
| `main.m` | App entry point (`UIApplicationMain`) |
| `AppDelegate.h/.m` | App delegate; holds the shared `Open4IDAuthClient` (Google-sign-in subclass) and wires the presentation anchor |
| `ViewController.h/.m` | Main UI: config fields, action buttons, session label, log console |
| `Open4IDSocialClient.h/.m` | `Open4IDAuthClient` subclass overriding the Google code-acquisition seam |
| `Open4IDSDKModule/module.modulemap` | Clang module map bridging the XCFramework's Swift-generated header so pure-ObjC consumers can `@import Open4IDSDK;` (the static-library XCFramework ships no `Modules/module.modulemap`); `Open4IDSDK-Swift.h` inside it is a symlink to the SDK slice's header (byte-identical across device/simulator slices) |
| `Info.plist` | App bundle config, custom URL scheme for callbacks |
| `ios-sdk-minimal-objc.xcodeproj/` | Xcode project (links `Open4IDSDK-0.3.3.xcframework` + SPM `GoogleSignIn-iOS`) |

## Building

1. Open `examples/ios-sdk-minimal-objc/ios-sdk-minimal-objc.xcodeproj` in Xcode.
2. Select a device or simulator target.
3. Build and run.

The SDK is linked as the prebuilt **XCFramework** at the repo root
(`../../Open4IDSDK-0.3.3.xcframework`); the project's `-fmodule-map-file`
build setting points Clang at `Open4IDSDKModule/module.modulemap` so
`@import Open4IDSDK;` resolves. The `GoogleSignIn-iOS` package is fetched
remotely via SPM for the Google sign-in override.

## ObjC API surface used

Every SDK call uses the `@objc` completion-handler twin:

```objc
NSError *error = nil;
[auth configureWithAppId:@"app_..."
             environment:@"development"
         publicSdkKey:@"sdk_pk_..."
                endpoint:@"https://id.open4id.com/api"
            redirectUri:@"com.example.app://open4id/callback"
                   scope:@"openid profile email"
               bundleId:@"com.example.app"
                  error:&error];
if (error) { /* error.domain == @"Open4IDSDK", error.code == error_code */ }

// Auth-state listener (login-state-changed event).
void (^unsubscribe)(void) = [auth onAuthStateChanged:^(AuthSession * _Nullable session,
                                                        UserInfo * _Nullable user) {
    if (session) { /* signed in */ } else { /* signed out */ }
}];

// Sign in as guest.
[auth continueAsGuest:^(AuthSession * _Nullable session, NSError * _Nullable error) {
    if (!error) NSLog(@"guest: %@", session.userId);
}];

// Sign out.
[auth signOut:^(NSError * _Nullable error) {
    if (!error) NSLog(@"signed out");
}];
```

Errors bridge as `NSError` with domain `Open4IDSDK`, the integer
`error_code` as the code, and the stable key in `userInfo[@"key"]`
(e.g. `client.auth.invalid_request`, `client.auth.provider_unavailable`).

## Login dialog from ObjC

The **Open login dialog** button mirrors the Swift sibling's
`prepareLoginUI()` + present. Because the SwiftUI dialog API
(`showOpen4IDLoginDialog(on:model:)`, `.open4IDLoginSheet`) and the
non-`@objc` `Open4IDAuthViewModel` cannot be called from Objective-C, the
SDK exposes an `@objcMembers` facade — `Open4IDLoginDialogObjC` — that
performs the same binding (locale, `setAuthClient`, `setBootstrap`,
sign-in mode) and presents the same centered-card dialog over UIKit:

```objc
// The last fetched bootstrap drives the provider list (nil = hide
// providers/guest until the host re-binds after a fresh bootstrap).
self.lastBootstrap = bootstrap; // store it in `[auth bootstrap:...]` callbacks

self.loginDialogHandle = [Open4IDLoginDialogObjC
    showOn:self                       // any UIViewController
    client:self.authClient            // the configured headless client
    bootstrap:self.lastBootstrap      // nullable
    localeTag:@"en"                   // resolved to en/vi; nil = en
    dismissOnSignIn:YES               // auto-close on sign-in (default YES)
    onSignedIn:^(NSString *provider) { NSLog(@"signed in %@", provider); }
    onSignedOut:^{ NSLog(@"signed out"); }
    onAccountDeleted:^{ NSLog(@"account deleted"); }];

// Imperative close, mirroring the Android dialog's close():
[self.loginDialogHandle close];
```

Inside the card, guest / email-password / GitHub / Apple / Google flows run
through the same configured client as the headless section, so both present
web sessions from the registered presentation anchor (`AppDelegate.m`).

## Notes

- The SDK's SwiftUI `ui/` layer (Phase 13 login view/dialog) is not directly
  reachable from ObjC — Swift global functions and the non-`@objc`
  `Open4IDAuthViewModel` are invisible to the generated header — so the SDK
  ships the `@objc` facade `Open4IDLoginDialogObjC` (see below); the example
  otherwise hand-builds its UIKit UI on the headless client.
- Google sign-in requires the `GoogleSignIn-iOS` SPM package and a valid
  GCP iOS OAuth client ID. Without one, the Google button reports
  `provider_unavailable` by design.
- GitHub and Apple flows need the production Portal bridge deployed and
  provider-console callback URIs registered for the sample bundle ID.