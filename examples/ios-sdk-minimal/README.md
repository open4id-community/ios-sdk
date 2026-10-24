# iOS SDK Minimal Example

Minimal SwiftUI app consuming the Open4ID iOS SDK (`sdks/ios`) at headless
parity with `examples/android-sdk-minimal`: editable configuration, the same
action order, and an append-only log console.

## Requirements

- Xcode 15+ (verified with Xcode 27.1), iOS 16+ simulator or device.
- The app links the SDK as the prebuilt **XCFramework**
  (`../../Open4IDSDK-0.4.0.xcframework`, repo root) — no registry dependency.
  GoogleSignIn is resolved via SPM from the sample project.

## Build & run

```sh
cd examples/ios-sdk-minimal
open ios-sdk-minimal.xcodeproj   # then pick an iPhone simulator and Run
```

Command line:

```sh
xcodebuild -project ios-sdk-minimal.xcodeproj -scheme ios-sdk-minimal \
  -destination 'platform=iOS Simulator,name=iPhone Duo' build
```

The app **auto-configures and bootstraps on launch** with the development
application's fixtures (the sample's bundle ID `com.open4id.example.ios` is
registered on it, native binding `platform: "ios"`), defaulting to the
production endpoint `https://id.open4id.com/api`. A successful launch logs:

```text
open4id-minimal: bootstrap ok: app=Login Show Case google=true
```

(the log console mirrors to the unified log, subsystem
`com.open4id.example.ios`, for automated verification via
`simctl launch` + `log show`).

## Actions

| Button | Notes |
| --- | --- |
| Load bootstrap | Re-fetches auth discovery for the configured app |
| Sign in with Google | Real GoogleSignIn-SDK sign-in through the sample's `Open4IDSocialClient` override — picker → server auth code → `player_google_authorize` → Open4ID session. See "Google sign-in" below |
| Continue as guest | Fresh guest session through the same PKCE exchange |
| Sign in with GitHub / Apple | Real `ASWebAuthenticationSession` flows through the per-app Portal bridges (`app.open4id.com/github-callback/<bundle id>`, `/apple-callback/<bundle id>`); the sample wires `setPresentationAnchor` to the scene window on launch. Apple's first-time sign-in shows the share/hide-email sheet (`scope=email`, `response_mode=form_post`) |
| Refresh session / Get user / Sign out / Delete account | Session lifecycle through the headless client |
| Sign in / Register / Forgot password | Native email/password flows (generic anti-enumeration responses) |

## Login UI

The sample also demonstrates the SDK's opt-in SwiftUI login UI
(`Open4IDAuthView` + `Open4IDLoginDialog`, Android-mirrored): the
**Open login dialog** button binds the shared `Open4IDAuthViewModel` to
the live client + bootstrap and presents the login dialog — a centered
card over a dimmed backdrop with Android-dialog geometry (92% width
capped at 480pt, wrap-content height, corner 12, tap-outside dismiss).
Inside the
card you get the same flows as the plain buttons above — password
sign-in/up, forgot-password, guest, readiness-driven provider buttons
(Google/GitHub/Apple), and the session-aware account view with
refresh/sign-out/delete — driven entirely through the headless
`Open4IDAuthClient`; the sample logs the `AuthListener` callbacks
(`onSignedIn`/`onSignedOut`/`onAccountDeleted`) into the same console.
The card auto-dismisses on sign-in (`dismissOnSignIn`, default true)
and stays open on sign-out.

Notes:

- The dialog observably fails closed when a provider is not offered by
  bootstrap (disabled provider → localized info line, no call).
- The fixture keeps the dialog locale pinned to `en`; the model exposes
  `setLocale` (the strings ship en + vi) for an in-app switcher.
- The UI layer is Swift-only and therefore absent from the generated
  ObjC header; the XCFramework recipe is unchanged. Provider marks are
  drawn at runtime as vector paths (the library ships no asset
  bundle).

## Google sign-in

The SDK leaves `getGoogleAuthorizationCode` as an overridable seam
(Android `protected`-method parity); the sample ships the override in
`Open4IDSocialClient.swift` using the
[Google Sign-In SDK for iOS](https://developers.google.com/identity/sign-in/ios)
(resolved via SPM from the sample project):

1. Add the Google Sign-In package to the app project.
2. Register a Google iOS-type OAuth client whose **bundle ID matches the
   app's** and add the client's reversed client ID as a URL scheme in the
   app's `Info.plist`.
3. Subclass and override (this is what `Open4IDSocialClient` does):

```swift
final class Open4IDSocialClient: Open4IDAuthClient {
    override func getGoogleAuthorizationCode(clientId: String,
                                              timeoutMs: Int) async throws -> String {
        // Force sign-out for a fresh picker, then
        // GIDConfiguration(clientID: <iOS-type client>, serverClientID: clientId
        //   // ^ clientId is the bootstrap Web client: the code must be
        //   //   issued FOR the server client to be exchangeable by Core API)
        // GIDSignIn.sharedInstance.signIn(withPresenting: ...) → serverAuthCode.
        // Map cancel → popup_closed, missing code → access_denied,
        // config gaps → provider_unavailable (gid_* fieldErrors carry the raw
        // GID error code/domain/message), timeout → popup_timeout.
    }
}
```

4. Register the override with the base client:
   `Open4IDClient(..., socialAuth: Open4IDSocialClient(...))`.

Live-proven end to end on a real iPhone: picker → server auth code →
Core API `player_google_authorize` → Open4ID session
(`signed in: sub=usr_…` in the log console).

Note: this flow needs a real device. On the iOS 27.1 simulator the OAuth
part succeeds but GoogleSignIn's internal keychain save is refused
(GID answers `keychain error`; every `SecItemAdd` shape fails
`-34018 errSecMissingEntitlement` for team-less simulator builds), so the
button surfaces the typed failure with `gid_*` diagnostics there.

The Android sample's `SocialAuthClient` shows the same override pattern for
its Play-Services flow.

## Configuration

The Configuration section mirrors the Android sample's fields, plus a
**Google iOS client ID** field for the GoogleSignIn override (defaults to
the wired GCP iOS client). For a
**real device**, change the redirect URI + Bundle ID to your own
registered app (the Portal must have the iOS platform registered with that
bundle ID, and the custom scheme must match the redirect scheme exactly).
