# Changelog

All notable changes to the Open4ID iOS/macOS SDK are documented here.
Distribution: SwiftPM resolves the plain-semver `v<version>` tag on the
GitHub SPM mirror
(`https://github.com/open4id-community/ios-sdk`); the prebuilt
`Open4IDSDK-<version>.xcframework.zip` lives in the monorepo's
`sdks/ios/dist/` with `SHA256SUMS` for Objective-C / binary consumers.
The monorepo tags every release `ios-v<version>` (lineage marker).

## 1.0.0 (2026-11-15)

- **App-open analytics**: `appOpen()` (ObjC `appOpen:`) sends the
  fire-and-forget cold-start ping to `client/app_open` with a locally minted
  installation id (`deviceIdentifier()`), persisted in the Keychain
  (`com.open4id.sdk.device`) so it survives relaunches and reinstalls; every
  Keychain failure falls back to an in-memory id. The ping never throws and
  never blocks startup; the server stores only a salted hash of the id.
  `Open4IDAuthClient.resetDeviceId()` is the debug/support reset hook.
  Every payment call now rides the same id beside the session
  (`device_id`/`device_platform` body fields) — attribution metadata the
  server hashes and never lets alter the money path.

- **Interactive restore for "Restore purchases".** New
  `Open4IDStoreKitPayments.restoreInteractive()` (ObjC
  `restoreInteractive:`) does what the passive `restore()` cannot: it asks
  the App Store account first (`AppStore.sync()`, which raises the store
  sign-in sheet on a device with no signed-in account or a receipt that does
  not yet carry the purchase) and only then runs the same ledger restore.
  Previously a reinstall with no store account signed in read an empty local
  cache and reported `verified=0` with no prompt, so a paid purchase looked
  lost. `restore()` and the automatic launch restore stay passive on
  purpose: a cold start must never present a store sign-in sheet.
- **New `SdkStoreSignInCancelledError`** (`140007`,
  `client.payment.store_sign_in_cancelled`). The player dismissed the store
  sheet, so **no** ledger request was made and nothing was restored. It is
  not retryable and must not be reported as "no purchases found". Any other
  sync failure maps to `SdkStoreUnavailableError` (`160003`, retryable).
- **Bearer-proved player calls rotate a stale token.** `deleteAccount()`,
  `linkEmail(email:password:)`, and `getUser()` now refresh an access token
  that has passed its 900 s lifetime before the request, through the same
  `ensureSession(minValidityMs:)` path the payment calls use. Previously they
  sent the stored token verbatim, so ~15 min after sign-in the server answered
  `401` and, for deletion, the call failed while still clearing the local
  session. Signed out they still throw `client.auth.not_authenticated`; none
  of them mints a guest.
- **`RestoreResult.storeSynced`** (additive, default `false`) is `true` only
  on the interactive path after the account sync completed. A completed sync
  with `verified == 0` is the honest "this store account owns none of our
  products" answer, distinct from the passive path's "nothing cached".
- **Sample and docs**: the pure-ObjC `ios-sdk-minimal-objc` Restore button
  now calls `restoreInteractive:` and logs cancellation, store failure, and
  `storeSynced` separately; the README documents the interactive/passive
  split and the consumable/expired-subscription limits.
- Tests: `PaymentsRestoreInteractiveTests` (8) — sync-once and before proof
  collection, passive paths never sync, cancellation and store failure both
  skip the ledger, the `storeSynced` matrix, the honest empty result, and a
  purchase owned by another credentialed account reported as `conflict`.
  Full suite: 271 tests, 1 skipped, 0 failures.
- Device-verified on an iPhone 12 against the App Store sandbox (all six
  restore cases): sheet on a signed-out account, typed cancellation on
  dismissal with no ledger request, recovery of a purchase after the guest
  account was deleted, and a passive launch restore that never prompts.
- No Core API change: the ledger already re-grants a store-verified proof
  while the owner is a movable guest, so the client only needed to send one.

## 0.8.8 (2026-11-12)

- **One event surface for hosts.** `Open4IDAuthClient.onEvent` delivers one
  `Open4IDEvent` for every state change a host used to re-publish itself:
  `auth` (sign-in/sign-out/refresh/restore/account deletion, with the
  sign-in method in `message`), `products` (bootstrap catalog and
  `loadProducts`), `entitlements` (publish, hydration, and the cleared
  signed-out snapshot), `purchase` (`verifyTransaction`/
  `verifyConsumable`, including a non-grantable consumable state),
  `restore` (`restore()`/`restore(proofs:)` with a verified/rejected/
  conflict summary), and `transaction` (ask-to-buy approvals and
  cross-device buys from `Transaction.updates`). `success`, `productId`,
  `message`, and `entitlements` carry the per-kind detail; `message` is a
  stable error key or a short summary and never a token or a store proof.
  The block is additive — every typed listener still fires — and is
  delivered on the callback queue (`setCallbackQueue(_:)`, main by
  default), not synchronously inside the operation. Setting `nil`
  detaches it.
- **`subscriptionState(productId:)`** (ObjC
  `subscriptionStateForProductId:`), on `entitlements()` and as a client
  convenience, replaces host-side recomputation from
  `isPurchased(productId:)`. It returns `.active`, `.grace` (billing
  retry), `.expired` (including a cached `active` row past `expiresAt`),
  `.none` (revoked-only, or no row while the snapshot is known), or
  `.unknown` (no snapshot yet, a product in neither catalog, or a
  consumable without entitlement keys). It reads the live catalog, then the
  catalog captured in the persisted snapshot, so it answers offline on a
  cold launch. Treat `.unknown` as *checking*, never as "locked".
- **Guest login split from the guest button.** `guest_enabled` stays the
  server capability (guest identities, guest-bound payments); the new
  `guest_button_visible` flag only decides whether the built-in dialogs
  render "Continue as guest". It defaults to `guest_enabled` when the Core
  API omits it, so older bootstraps and configurations behave exactly as
  before. Anonymous checkout is `guest_enabled = true` +
  `guest_button_visible = false`: purchases work without a login screen
  while the dialog shows only real sign-in methods. Exposed as
  `LoginReadiness.guestButtonVisible` (ObjC `guestButtonVisible`) and
  `Open4IDAuthLayout.Model.guestButtonVisible`.
- **Purchase preflight.** `Open4IDStoreKitPayments.purchase` now checks for
  a usable identity before opening the StoreKit sheet: with no session and
  guest login disabled it throws `client.auth.not_authenticated` instead of
  charging a player whose verify would be rejected. Hosts get
  `canPurchase()` and `requiresSignIn()` for shop gating (fail-closed
  before the first bootstrap). The guest identity is still minted only
  after the player confirms the sheet.
- Tests: `EventsTests` (15) — all six event kinds, the subscription-state
  matrix (including the hydrated-cache and offline cases), main-queue
  delivery, and detaching. Full suite: 253 tests, 1 skipped, 0 failures.
- **Publisher binaries**: `Open4IDSDK-0.8.8.xcframework.zip` in
  `sdks/ios/dist/` (device, simulator, and macOS slices; library-evolution
  swiftinterfaces and the per-slice Clang module map). SHA-256 in
  `SHA256SUMS`; the artifact is the one vendored into bedtimefairytales.

## 0.8.0 (unreleased)

- **Paid state survives a relaunch.** The SDK now persists the last
  entitlement rows **and the catalog they were resolved against**, and
  rehydrates them inside `configure` before any network call. A cold or
  offline launch answers `entitlements().has(_:)`,
  `hasAny(_:)`, and `isPurchased(productId:)` immediately, instead of
  showing an empty shop until the first `refresh()`/`restore()`/verify.
  The hydrated snapshot is flagged `isFromCache == true` with
  `savedAtMillis`/`savedAt` set to when those rows were fetched, so a host
  can render "last known" state without pretending it is authoritative.
- **The cache is scoped and cleared.** Each player gets their own item
  (`KeychainSnapshotStore` account `"<account>.<playerId>"`), and the
  snapshot carries `appId`/`bundleId`/`playerId`: a foreign or corrupt item
  reads as "nothing cached". Sign-out, `reset()`, and a player switch clear
  the departing player's cache only; another player's cache is untouched.
  Cached rows keep the server's `state`/`expiresAt` and still go through the
  same time-aware `isUsable` check, so a lapsed subscription stays locked
  offline.
- **`SnapshotStore` is an `@objc` protocol.** The default backend is
  `KeychainSnapshotStore` (same trust boundary as `KeychainSessionStore`,
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), so paid state also
  survives a reinstall. `MemorySnapshotStore` is used automatically when the
  session store is memory-only (hermetic hosts and tests never write grants
  to the Keychain). Opt out explicitly with `setSnapshotStore(nil)`
  (`setSnapshotStoreMemoryOnly` from Objective-C); pass an adapter to
  `setSnapshotStore:` to namespace several applications in one process.
- **`start()` runs the documented startup order in one call.** It creates
  the built-in StoreKit adapter *before* bootstrap (unless the host already
  registered a `payments().proofSource`), bootstraps, waits for the launch
  restore that bootstrap scheduled, and only then signs in as a guest when
  nothing was restored. It is single-flight and safe to call again
  (concurrent callers share one sequence), and a failed start (offline first
  launch) leaves the cached paid state readable and can simply be retried.
  **A stored session is never replaced by a guest.**
- **`sessionState` and `hasStoredSession()`.** `sessionState` answers
  `none`/`guest`/`authenticated`/`expired` for branching, replacing the
  `isAuthenticated()` footgun (that one is about the **access token** only).
  `.expired` still means a session exists: `getSession() != nil` and every
  payment call rotates the token — do not mint a new guest on it.
  `hasStoredSession()` reports whether a previous process persisted a
  session for this app/environment, so a host can skip a first-launch
  onboarding screen.
- **Listeners fire on a host-chosen queue.** Every SDK callback —
  entitlement changes, purchase outcomes, auth-state changes, and
  server-callback errors — is delivered on `setCallbackQueue(_:)`, which
  defaults to the **main queue**. Hosts stop wrapping each listener in
  `dispatch_async(dispatch_get_main_queue(), …)`. Pass `nil` to deliver
  synchronously on the publishing thread (headless servers, tests). State
  is already settled when the callback runs, so `current()` is safe to read
  inside a listener.

## 0.7.1 (unreleased)

- **Restore chunks itself.** `payments().restore()`,
  `restore(proofs:)`, `storeKitPayments().restore()`, and the launch
  restore now split the collected proofs into requests that respect both
  server bounds: at most **20 proofs** and at most **48 KiB of serialized
  JSON** per request. A catalog with more owned products than one request
  can carry now restores completely instead of failing wholesale with
  `field_errors.body = too_large`. Hosts no longer need their own
  batching loop, and the `proofs` list is never truncated: every proof is
  submitted.
- **Shape errors are bisected, transients are not.** A chunk rejected for
  its shape (`100001`–`100003`) is split until the offending proof is
  isolated; a single proof that still fails is counted in
  `RestoreResult.rejected` and logged, while the rest of the restore
  continues. A rate limit (`150001`), an outage (`160001`/`160003`), an
  auth failure, or a transport error aborts immediately — retrying
  smaller cannot help and would multiply requests.
- **Proofs over the public field cap are rejected without a request.** A
  proof whose `jws_representation`/`purchase_token` exceeds the Core API's
  16384-byte limit is counted as `rejected` and reported in diagnostics
  instead of spending a round trip.
- **One published snapshot per restore.** The server returns the full
  entitlement list on every call, so the SDK publishes the last successful
  chunk once. `RestoreResult` sums `verified`/`rejected`/`conflict`
  across chunks.
- **A distinct oversize-body error.** `SdkPayloadTooLargeError`
  (`100005`, key `client.payment.request_too_large`) covers both the new
  Core API `413` response and the legacy `400`/`100003` shape with
  `field_errors.body = too_large`, so host branching works against either
  server release. The SDK chunks restores, so this normally never
  surfaces.
- **`SdkError.isRetryable`.** `true` for `150001`, `160001`, and `160003`;
  `false` for shape, auth, conflict, not-found, internal, and oversize
  errors. Also exposed as `retryable` in the bridged `NSError.userInfo`,
  so hosts stop matching codes by hand.
- **The XCFramework ships a Clang module map.** Each slice carries
  `Headers/module.modulemap` (the path Xcode reads for a library
  XCFramework) and `Modules/module.modulemap`, so an Objective-C host adds
  only the framework and writes `@import Open4IDSDK;` — no
  `FRAMEWORK_SEARCH_PATHS`, `HEADER_SEARCH_PATHS`, `-fmodule-map-file`, or
  header symlink. The `Open4IDSDKModule` adapter in the examples is no
  longer required for new integrations.
- **Core API (deployed after this release).** The client payment routes
  raise their body cap from 65536 to **262144 bytes** and answer an
  oversized body with `413` / `client.payment.request_too_large` /
  `100005` (`field_errors.body = too_large` is preserved). 0.7.1 maps
  both shapes, so deploying the server after the SDK keeps host branching
  stable.

## 0.7.0 (2026-11-12)

- **ObjC session persistence (no Swift shim).** `SessionStore` is now an
  `@objc` protocol and `KeychainSessionStore` is `@objcMembers`, so an
  Objective-C / Objective-C++ host enables persistence with
  `[client setSessionStore:[[KeychainSessionStore alloc] init]]` — or
  implements its own `Open4IDSessionStore` backend — without adding a
  Swift file. `setSessionStoreMemoryOnly` stays the memory-only opt-out.
- **Time-aware entitlement usability.** `Entitlement.isUsable` now treats
  a cached `active` row past its `expiresAt` as unusable (the server
  recomputes on read, but between refreshes the client owns the check),
  while a `grace` row keeps its original (past) expiry by design — the
  grace-window end is server-side and arrives as the next state on a later
  read. Parsed dates (`expiresAtDate`/`grantedAtDate`/`updatedAtDate`,
  `remainingSeconds`), `has(_:at:)`, snapshot and client `hasAny(_:)`,
  `isPurchased(productId:)` (catalog row → entitlement keys), and
  `entitlement(_:)` round out the surface.
- **Launch restore reconciles with the store.** When a proof source is
  registered, the stored-session hydration now also submits the store's
  current receipts instead of only refreshing the ledger: renewals
  recorded only by the store, and purchases made before persistence
  existed, repair themselves at launch without a Restore tap.
- **Store facts on the purchase outcome.** `Open4IDPurchaseOutcome`
  carries `expirationDate`, `originalPurchaseDate`, and `environment`
  (`Sandbox`/`Production`/`Xcode`) parsed from the StoreKit transaction —
  hosts answer "does Apple think this is still active?" without importing
  StoreKit.
- **Opt-in diagnostics.** `Open4IDDiagnostics.level = .info` +
  `Open4IDDiagnostics.onLog` emit redacted lines (config with the masked
  SDK key, entitlement rows on every publish, restore counts, verify
  results, launch-hydration failures as error keys). Off by default; the
  JWS, tokens, and the full key are never logged.
- **Store timing and environment docs.** The guide adds the
  sandbox/TestFlight renewal-rate table, the SDK-environment vs
  store-environment mapping, App Store Server Notifications guidance, and
  a "Subscription still active after 5 minutes" troubleshooting entry.
- **The session persists by default (Keychain).** `configure` without a
  `store` falls back to `KeychainSessionStore()` instead of the previous
  memory-only default: the session — and the guest identity behind it —
  survives relaunches and, because Keychain items outlive the app sandbox,
  uninstall/reinstall cycles. The same player keeps the same account, the
  server ledger keeps binding grants to it, and the launch restore (below)
  rehydrates paid state without needing store proofs. Opt out with
  `setSessionStore(nil)` (sticky memory-only; also bridged to Objective-C
  as `setSessionStoreMemoryOnly`) or pass `MemorySessionStore()` explicitly
  (tests, kiosks, multi-tenant shells). Together with the launch restore
  this fixes "paid a package, killed the app, reopened — paid state gone".
- **Paid state survives a restart (launch restore).** After the first
  `bootstrap()` that advertises a payments catalog, the SDK rehydrates paid
  state once per process: a stored session refreshes its ledger rows, and a
  missing session signs in as a guest (when guest login is enabled) and
  restores through the registered proof source — so a package bought in a
  previous run is active again after relaunch without host code. The result
  arrives through `entitlements().onChanged` like every other publish; a
  failure stays silent and leaves paid state "unknown" (the host's explicit
  `restore()` / `refresh()` still work unchanged). Opt out with
  `payments().autoRestoreOnLaunch = false` set before the first
  `bootstrap()`. Creating `storeKitPayments()` after the bootstrap runs one
  idempotent retry with the built-in proof source, so a store set up late
  still repairs a session that did not survive the restart.
- Example (`examples/ios-sdk-minimal`): the session now persists across
  relaunches (`configure(store: KeychainSessionStore())` — the same player
  identity keeps the ledger binding and consumable deliveries idempotent),
  and the Payments section shows the live paid state driven by
  `entitlements().onChanged`.

## 0.6.0 (2026-11-04)

- **Built-in StoreKit 2 payments store** (`PaymentsStoreKit.swift`): the
  SDK now owns the store glue the example apps used to ship — the shop UI
  stays host-owned (the SDK ships no shop view, matching the headless
  design). One client call
  — `auth.storeKitPayments()` (new stable namespace beside `payments()` /
  `entitlements()`) — returns `Open4IDStoreKitPayments`, which
  - loads the shop rows **from the SDK request**: the `app_store` rows of the
    Open4ID catalog (the bootstrap snapshot via `payments().products()`)
    joined with the StoreKit 2 products resolved for them
    (`Open4IDStoreProduct`, `loadProducts()` — no hardcoded product ids, no
    host-side catalog parsing);
  - runs the **one-call purchase pipeline** `purchase(_:)` (pass the catalog
    row the host rendered the Buy button from — no re-lookup, no stale
    -snapshot failure) and the by-id variant `purchase(productId:)`, which
    resolves the id against the Open4ID catalog and refreshes the bootstrap
    snapshot once when it does not know the id: StoreKit sheet → local JWS
    verification → `TransactionProof.appStore` → `verifyTransaction`
    (one_time/subscription) or `verifyConsumable` (consumable) →
    `Transaction.finish()` after a successful verify — answering an
    `Open4IDPurchaseOutcome` whose `verified` / `cancelled` / `pending` kinds
    are the only branch the host needs;
  - **self-sufficient restore**: a built-in `PaymentProofSource` over
    `Transaction.currentEntitlements` is registered on the payments
    namespace automatically, so `payments().restore()` collects store proofs
    with zero host wiring;
  - **`Transaction.updates` listener**: the store iterates
    `Transaction.updates` from creation (Apple's guidance: listen before any
    purchase), so purchases completing outside a direct `purchase` call —
    an approved ask-to-buy, a buy made on another device of a
    universal-purchase app — are verified through the same pipeline,
    finished, and reported via `onTransactionUpdate` (main queue, optional).
    A transaction whose verify fails or whose product is not an `app_store`
    catalog row stays unfinished, so StoreKit re-delivers it on the next
    launch — nothing is granted unverified and nothing is lost.
  Every method has an `@objc` completion twin, so Objective-C and Unity hosts
  get the full feature with no Swift file (StoreKit 2 is a Swift-only API;
  the SDK owns that side now). StoreKit is a system framework — still no
  package dependency. The headless contract is unchanged; hosts with their
  own store client keep using `payments()` directly.
- **Examples**: `examples/macos-sdk-minimal` (SwiftUI) and
  `examples/macos-sdk-minimal-objc` (AppKit) slimmed to the SDK's built-in
  store — the per-app `Open4IDStoreKitBridge.swift` / `StoreKitBridge.swift`
  are deleted and each sample renders its own Buy buttons from the
  `Open4IDStoreProduct` rows the SDK returns (shop UI stays host-owned);
  the ObjC sample is pure Objective-C (`@import Open4IDSDK;`) and resolves
  the SDK from the local `sdks/ios` package like the iOS examples. The three
  duplicated `Open4IDStoreConfig.storekit` fixtures are
  deduplicated into one shared `examples/Open4IDStoreConfig.storekit` — the
  path every example scheme already references (a development fixture for
  local StoreKit testing only; normal SDK users never author one, and the
  shop loads its products from the SDK catalog request).

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
  package dependency: the game buys through StoreKit, Unity IAP and forwards the StoreKit 2 `jwsRepresentation` with
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
  redirects or the origin-derived page for web redirects (an explicit
  `callbackUri` override wins; loopback HTTP is accepted in
  development) — then posts `facebook_code` + `facebook_redirect_uri`
  to `POST /client/player_facebook_authorize` exactly like the GitHub
  flow; the server exchanges the code with the Vault-backed App Secret
  (appsecret_proof-guarded Graph calls) and answers the same
  single-use PKCE-bound authorization code. Requires the Facebook
  provider enabled in bootstrap (`LoginReadiness.facebook`);
  cancelled / denied / timed-out / blocked sessions fail like the
  GitHub flow. Provider-mark parity: the Facebook glyph sits on Apple's
  24.4pt canvas so the blue disc reads the same size as the Apple mark
  (both glyphs fill their viewBoxes edge to edge, matching the web
  element's equal `1.1rem` marks).
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
