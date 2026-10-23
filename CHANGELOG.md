# Changelog

All notable changes to the Open4ID iOS SDK are documented here.
Distribution: SwiftPM resolves the plain-semver `v<version>` tag on the
GitHub SPM mirror
(`https://github.com/open4id-community/ios-sdk`); the prebuilt
`Open4IDSDK-<version>.xcframework.zip` lives in the monorepo's
`sdks/ios/dist/` with `SHA256SUMS` for Objective-C / binary consumers.
The monorepo tags every release `ios-v<version>` (lineage marker).

## 0.4.0

- **Facebook Sign-In (web session)**: new
  `signInWithFacebook(callbackUri:)` (async/await) and
  `signInWithFacebookWithCallbackUri:completion:` (`@objc`) on the
  headless client, and a "Sign in with Facebook" row in the login UI
  (rendered between GitHub and Apple — the same order as the JS
  element). The SDK opens an `ASWebAuthenticationSession` at the
  Facebook OAuth dialog (pinned Graph API `v26.0`, `scope=email`) bound
  to the game callback URI — default the per-app Portal bridge
  `<portalOrigin>/facebook-callback/<bundleId>` for custom-scheme
  redirects.
- **Portal-origin setter for Objective-C**: the throwing
  `setPortalOrigin(_:)` did not bridge to Objective-C; the new
  `setPortalOriginWithPortalOrigin:error:` overload (same
  `NSErrorPointer` pattern as `configure`) lets pure-ObjC hosts point
  the per-app social bridges at a development Portal.
- **Web-session timeout deadlock fix**: leaving the
  `ASWebAuthenticationSession` consent prompt unanswered previously
  hung every awaiting flow forever (`cancel()` silently skipped the
  completion handler, so the timeout task group never resumed). The
  timeout path now resumes the continuation with
  `client.auth.popup_timeout` and cancels the session; late completions
  are dropped.
- **Publisher binaries**: `Open4IDSDK-0.4.0.xcframework.zip` in
  `sdks/ios/dist/` (both slices, library-evolution swiftinterfaces,
  generated ObjC header carrying the two new `@objc` surfaces), with
  `SHA256SUMS` and install steps in `sdks/ios/dist/README.md`.
- **Example apps** (`examples/ios-sdk-minimal(-objc)`): Portal-origin
  config field on both samples, `SIMCTL_CHILD_OPEN4ID_*` launch-time
  env overrides, and `SIMCTL_CHILD_OPEN4ID_AUTOTEST=facebook|github|apple`
  auto-run hooks.
- **Test fixes**: the `Open4IDSDKObjCIntegrationTests` sign-in tests
  bootstrap before signing in (returning the 17 pre-existing
  `client.auth.not_bootstrapped` failures to green).
- **Tag scheme note**: the monorepo's plain `v0.4.0` belongs to the JS
  SDK lineage, so this release tags the monorepo `ios-v0.4.0` only;
  SPM consumers resolve the plain `v0.4.0` on the GitHub SPM mirror.
  Monorepo-internal consumers stay on `from: "0.3.3"`.

## 0.3.3

- **First SwiftPM release** of the iOS SDK (phases 2–14): annotated
  tags `v0.3.3` (plain semver, resolves via SPM) and `ios-v0.3.3`
  (lineage marker) at the same commit, which also added the
  repository-root `Package.swift` shim so remote
  `.package(url:, from: "0.3.3")` works despite the development
  manifest living in `sdks/ios/`.
- **Platform surface**: `configure` validation, `bootstrap` (native
  wire shape `platform: "ios"` + `bundle_id`), session lifecycle
  (single-use code + PKCE verifier exchange, single-flight `refresh()`,
  generation guard), the player flows (`signInWithPassword`,
  `continueAsGuest`, `register`, `resendVerification`, `verifyEmail`,
  `requestPasswordReset`, `resetPassword`, `linkEmail`, `deleteAccount`),
  `notifyServer` receipt replay, auth-state listeners, session-store
  restore (`KeychainSessionStore` opt-in adapter), and a DeviceCheck
  `Attestation.collect()` probe (audit-only).
- **Social providers**: Google as an overridable seam
  (`getGoogleAuthorizationCode`; hosts plug in the Google Sign-In SDK —
  `Open4IDGoogleAuthorizationCodeProviding` + `setGoogleAuthorizationCodeProvider:`
  let pure-ObjC hosts supply the code), GitHub and Apple driven by the
  SDK's own `ASWebAuthenticationSession` (`iOS 17.4+` `Callback` API;
  Apple posts `apple_code` + `apple_return_uri` through the per-app
  Portal bridge form_post).
- **Login UI** (Phase 13): the SwiftUI provider-row dialog — Google,
  GitHub, Apple rows, credentials forms, en/vi strings.
- **Objective-C surface** (Phase 14): `@objc` completion-handler twin
  for every `async` method (`NSError` domain `Open4IDSDK` + integer
  code), `@objcMembers` model bridging, `NSErrorPointer` `configure`
  overload, `onServerCallbackErrorObjC`, and the `Open4IDLoginDialogObjC`
  / `Open4IDLoginDialogHandleObjC` facade exposing the login dialog to
  pure ObjC hosts; `Open4IDSDKObjCIntegrationTests` bundle and the
  verified example app `examples/ios-sdk-minimal-objc`.
- **Publisher binaries**: the first `Open4IDSDK-0.3.3.xcframework.zip`
  in `sdks/ios/dist/` (device + simulator slices, library-evolution
  swiftinterfaces, generated ObjC header) with `SHA256SUMS`; the GitHub
  SPM mirror (`open4id-community/ios-sdk`) published a root
  `binaryTarget` manifest fetching this zip, keeping the Swift sources
  private while Swift consumers resolve `from: "0.3.3"`.
- **Example app**: `examples/ios-sdk-minimal` (SwiftUI) mirroring the
  Android sample's action order with an append-only log console and
  auto configure + bootstrap on launch.
