# Changelog

All notable changes to the Open4ID iOS/macOS SDK are documented here.
Distribution: SwiftPM resolves the plain-semver `v<version>` tag on the
GitHub SPM mirror
(`https://github.com/open4id-community/ios-sdk`); the prebuilt
`Open4IDSDK-<version>.xcframework.zip` lives in the monorepo's
`sdks/ios/dist/` with `SHA256SUMS` for Objective-C / binary consumers.
The monorepo tags every release `ios-v<version>` (lineage marker).

## 0.5.0

- **App Store consumables**: the shared catalog accepts an `app_store`
  `consumable` row (empty `entitlements`; a consumable naming an entitlement
  is still rejected in either store), `verifyConsumable(_:)` now substantiates
  an `TransactionProof.appStore` proof and returns `ConsumableReceipt` (the
  `@objc` twin calls back with the receipt), and `verifyTransaction` keeps
  skipping the entitlement publish when the response carries a `delivery`
  block so a consumable payload cannot wipe the cached snapshot. Apple has no
  server-side consume, so the Open4ID ledger is the only consume record; the
  receipt's `transaction_ref` is the game's idempotency key, and the
  `already_delivered` replay guard keeps a re-verified JWS from re-delivering.
  Google Play consumable consumption, server-side store acknowledge, and
  partial-refund reconciliation remain Android-only; see the Android SDK
  README.
- **Headless payments and entitlements**: new `Open4IDPayments`
  (`payments()`), `Open4IDEntitlements` (`entitlements()`), and the
  `PaymentsTypes` value types, with `@objc` bridges matching the existing
  Objective-C surface. The SDK never opens a purchase sheet and adds no
  package dependency: the game buys through StoreKit, Unity IAP, or
  RevenueCat and forwards the StoreKit 2 `jwsRepresentation` with
  `verifyTransaction(TransactionProof.appStore(...))`. Core API
  re-verifies the JWS with Apple before granting anything; there is no
  `verifyReceipt` fallback.
- **Entitlement snapshot**: `entitlements().refresh()` reads the
  server-derived rows, `has(_:)` is true only for `active`/`grace`, and
  `list()` keeps expired/revoked history. The snapshot is cleared when
  the signed-in player changes or signs out.
- **Catalog from bootstrap**: `payments().products()` returns the public
  `payments` block (product id, platform, type, entitlement keys) without
  a network call. A missing or malformed block yields a disabled catalog,
  never `nil`.
- **Restore**: `payments().restore()` recomputes from the ledger;
  `restore(proofs:)` accepts up to 20 optional proofs and reports
  `verified`/`rejected` counts plus `conflict` (valid proof, purchase owned
  by another credentialed account) with `hasConflict`.
- **Restore proof source**: `payments().proofSource` registers a
  `PaymentProofSource` (an `@objc` protocol) backed by the StoreKit client the
  host already owns, so `restore()` also submits the purchases StoreKit
  reports (`Transaction.currentEntitlements`, optionally after
  `AppStore.sync()`). One call then recovers a purchase both after a restart
  (stored session) and after a reinstall (fresh guest, same Apple ID), and the
  SDK keeps its no-dependency rule. A source error or the 10 s bound degrades
  to a ledger-only restore and sets `RestoreResult.proofsUnavailable`; explicit
  `restore(proofs:)` never consults the source, and `entitlements().refresh()`
  stays the ledger-only read.
- **Guest purchases**: `verifyTransaction` and `restore` sign in as a guest
  automatically when there is no session and the application allows guest
  login, so an anonymous purchase works without host code. With guest login
  disabled the call throws `client.auth.not_authenticated`.
- **Store-account restore**: a store-verified proof moves the purchase only
  while the current owner is still an anonymous guest, so a reinstall or a
  fresh guest on the same Apple ID restores what it paid for. Once the owner
  has an email or social identity the purchase is sticky: verify throws
  `SdkConflictError` and restore reports `conflict`, so a shared Apple ID
  cannot take a grant away from the paying account.
- **Proof hygiene**: `TransactionProof.description` redacts the JWS, and
  the SDK never logs or persists proof material.
- **Token freshness**: every payment call (`verifyTransaction`, `restore`,
  `entitlements().refresh()`) rotates a stale access token through
  `ensureSession` first, so a session older than the 900 s token lifetime
  no longer fails with `auth.token.invalid` — the case for a store sheet
  left open past the token's life.
- **Native macOS**: the same package now targets macOS 13+. A native macOS
  build asserts `platform: "macos"` with `bundle_id` on bootstrap and every
  player request (Mac Catalyst keeps `ios`), the AppKit login helpers present
  the dialog as a sheet, and `Scripts/build-xcframework.sh` emits a macOS
  slice alongside the iOS device/simulator slices. Enable the `macos`
  platform in the Publisher Portal for the Mac app's bundle id. The macOS App
  Store IAP path is live-verified end to end with `examples/macos-sdk-minimal`
  (2026-11-02).
- **New typed errors**: `SdkStoreUnavailableError` (`160003`, retryable, still
  matches `SdkUnavailableError`), `SdkNotFoundError` (`130004`),
  `SdkConflictError` (`140006`, `client.payment.owned_by_another_account`),
  plus field-level validation errors for proof submissions.
- **Publisher binaries**: `Open4IDSDK-0.5.0.xcframework.zip` in
  `sdks/ios/dist/` — the iOS device, iOS simulator, and macOS slices, built
  with `BUILD_LIBRARY_FOR_DISTRIBUTION` swiftinterfaces; this is the first
  release that ships the macOS slice.
- **Tag scheme note**: the monorepo tags this release `ios-v0.5.0` (lineage);
  SPM consumers resolve the plain `v0.5.0` on the GitHub SPM mirror
  `open4id-community/ios-sdk`.

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
