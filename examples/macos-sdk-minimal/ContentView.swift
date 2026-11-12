import SwiftUI
import os
import Open4IDSDK

/// Minimal **macOS App Store IAP test harness** for the Open4ID SDK.
///
/// Scope is deliberately narrow: **payments only, no login UI**. The payment
/// feature lives in the SDK — `client.storeKitPayments()` loads the shop rows
/// from the Open4ID catalog request and runs the StoreKit 2 purchase pipeline
/// (sheet → JWS proof → verify → finish) — while **the shop UI stays
/// host-owned**: this sample renders its own Buy buttons from the
/// `Open4IDStoreProduct` rows the SDK returns, the same way a game would.
/// There is no shop view in the SDK on purpose.
///
/// There is no social/provider/browser flow here, so no `ASWebAuthentication`
/// anchor, URL-scheme callback, or Portal origin is needed. The SDK still
/// requires a `redirectUri` at `configure` time; it is a placeholder that the
/// IAP path never uses. A purchase that has no session signs in as a guest
/// automatically, which requires guest login to be enabled for the
/// application.
struct ContentView: View {

    // MARK: - Configuration

    @State private var appId = envDefault("APP_ID",
        "app_4a17c6406abaefdf0d9a705e7175b37c")
    @State private var environment = envDefault("ENVIRONMENT", "development")
    /// The public SDK key must allow the `macos` platform (Portal → SDK keys).
    @State private var publicSdkKey = envDefault("SDK_KEY",
        "sdk_pk_1c91d1ee8bcf04e9226c09f291bd18c21ceeaa6f61b34203")
    @State private var endpoint = envDefault("ENDPOINT", "https://id.open4id.com/api")
    /// Required by `configure`; unused by the IAP path (no login/callback).
    @State private var redirectUri = envDefault("REDIRECT_URI",
        "com.open4id.example.ios://open4id/callback")
    /// The Mac app's bundle id. This is the universal-purchase identity: the
    /// same bundle id as the iOS app, registered on both the `ios` and `macos`
    /// platform entries, and matching the App Store
    /// `payments.app_store.bundle_id` used for JWS verification.
    @State private var bundleId = envDefault("BUNDLE_ID", "com.open4id.example.ios")

    // MARK: - State + log

    @State private var bootstrapApp = "-"
    @State private var logLines: [String] = ["[open4id-iap] Ready (macOS)."]
    @State private var busy = false

    // MARK: - Payments state

    /// Live paid-state line, driven by `entitlements().onChanged`: the SDK
    /// refreshes it on purchase, on the automatic launch restore, and on
    /// sign-in/sign-out. The session itself persists by default (Keychain),
    /// so a package bought in a previous run is active again right after a
    /// relaunch.
    @State private var paidText = "unknown (not fetched)"
    @State private var paidUnsubscribe: (() -> Void)?

    // MARK: - Shop (host-owned UI over the SDK's built-in store)

    /// Shop rows from the SDK: the `app_store` catalog rows joined with the
    /// StoreKit products (name/price). The sample renders one Buy button per
    /// row; the SDK owns everything behind the button.
    @State private var shopRows: [Open4IDStoreProduct] = []

    /// Console mirror for automated verification (unified log subsystem
    /// `com.open4id.example.macos`).
    private let console = Logger(subsystem: "com.open4id.example.macos",
                                 category: "iap")

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    field("App ID", $appId)
                    field("Environment", $environment)
                    field("Public SDK key", $publicSdkKey)
                    field("Endpoint", $endpoint)
                    field("Bundle ID", $bundleId)
                    field("Redirect URI", $redirectUri)
                }

                Section("Bootstrap") {
                    LabeledContent("Application", value: bootstrapApp)
                    Button("Load bootstrap") { run(loadBootstrap) }
                }

                Section("Payments (App Store)") {
                    Button("Load shop (SDK store)") { run(loadShop) }
                    ForEach(shopRows, id: \.product.productId) { row in
                        Button("Buy \(row.product.productId) [\(row.product.type)]"
                               + (row.displayPrice.map { " \($0)" } ?? "")) {
                            run { try await buy(row) }
                        }
                        .disabled(!row.isResolvable)
                    }
                    if shopRows.isEmpty {
                        Text("(no shop rows — load the shop first)")
                            .foregroundColor(.secondary)
                    }
                    Button("Restore purchases") { run(restorePurchases) }
                    Button("Entitlements (ledger)") { run(refreshEntitlements) }
                    LabeledContent("Paid state", value: paidText)
                    LabeledContent("StoreKit", value:
                        "\(shopRows.filter { $0.isResolvable }.count) products")
                }

                Section("Log") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(minHeight: 220)
                }
            }
            .navigationTitle("Open4ID IAP (macOS)")
            .disabled(busy)
        }
        .frame(minWidth: 680, minHeight: 520)
        .onAppear {
            // Paid state updates itself: purchases, the SDK's automatic
            // launch restore (once per process, after the first bootstrap
            // with a payments catalog), and sign-in/sign-out all land here.
            paidUnsubscribe = appClient.entitlements().onChanged { snapshot in
                Task { @MainActor in
                    paidText = Self.paidDescription(snapshot)
                }
            }
            paidText = Self.paidDescription(appClient.entitlements().current())
            // Auto configure + bootstrap on launch so a launch proves the
            // live path in the console without tapping anything. Bootstrap is
            // what loads the payment catalog and enables the guest session
            // the first purchase needs.
            Task {
                do {
                    try configureClient()
                    // One call enables the whole payment feature: products
                    // from the SDK catalog request, the StoreKit purchase
                    // pipeline, the restore proof source, and the
                    // Transaction.updates listener. The shop UI stays this
                    // sample's job.
                    let store = appClient.storeKitPayments()
                    // Ask-to-buy approvals and cross-device buys complete
                    // outside the Buy button's pipeline; the SDK verifies and
                    // finishes them automatically and reports the outcome here.
                    store.onTransactionUpdate = { outcome in
                        if outcome.isVerified {
                            append("update \(outcome.productId): verified — granted "
                                + "(ask-to-buy approval or cross-device buy); "
                                + "refresh entitlements")
                        } else {
                            append("update \(outcome.productId): \(outcome.kind)")
                        }
                    }
                    let bootstrap = try await appClient.bootstrap()
                    bootstrapApp = bootstrap.displayName ?? bootstrap.appId
                    append("bootstrap ok: app=\(bootstrapApp) "
                        + "payments=\(bootstrap.payments.enabled)")
                    // Debug hook for automated verification: launch with
                    // OPEN4ID_AUTOTEST=payments to auto-run the rehearsal
                    // (shop load + purchase of the first resolvable row; the
                    // StoreKit sheet needs the human's confirm).
                    if ProcessInfo.processInfo.environment["OPEN4ID_AUTOTEST"] == "payments" {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        try await loadShop()
                        if let row = shopRows.first(where: { $0.isResolvable }) {
                            append("autotest: buying \(row.product.productId)")
                            try await buy(row)
                        }
                    }
                } catch {
                    append("bootstrap failed: \(Self.describe(error))")
                }
            }
        }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("", text: text)
                .textFieldStyle(.plain)
        }
    }

    // MARK: - Actions

    private func run(_ action: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try configureClient()
                try await action()
            } catch {
                append("failed: \(Self.describe(error))")
            }
        }
    }

    /// Typed-error detail for the log console: stable key plus field errors,
    /// so a failure names its exact gate.
    private static func describe(_ error: Error) -> String {
        var detail = "\(error)"
        if let sdkError = error as? SdkError,
           let fields = sdkError.errorUserInfo["field_errors"] as? [String: String],
           !fields.isEmpty {
            detail += " \(fields)"
        }
        return detail
    }

    private func configureClient() throws {
        try appClient.configure(appId: appId,
                                environment: environment,
                                publicSdkKey: publicSdkKey,
                                endpoint: endpoint,
                                redirectUri: redirectUri,
                                bundleId: bundleId)
    }

    /// One-line paid-state summary for the Payments section.
    private static func paidDescription(_ snapshot: EntitlementSnapshot?) -> String {
        guard let snapshot else { return "unknown (not fetched)" }
        guard !snapshot.entitlements.isEmpty else { return "none" }
        let list = snapshot.entitlements
            .map { "\($0.key) [\($0.state)]" }
            .sorted()
            .joined(separator: ", ")
        return "\(snapshot.entitlements.count) row(s): \(list)"
    }

    private func append(_ line: String) {
        logLines.append(line)
        print("[open4id-iap] \(line)")
        console.notice("open4id-iap: \(line, privacy: .public)")
        persistLog()
    }

    /// Mirrors the log console into Documents/open4id-log.txt so a session can
    /// be inspected afterwards.
    private func persistLog() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("open4id-log.txt")
        try? logLines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadBootstrap() async throws {
        let bootstrap = try await appClient.bootstrap()
        bootstrapApp = bootstrap.displayName ?? bootstrap.appId
        append("bootstrap ok: app=\(bootstrapApp) payments=\(bootstrap.payments.enabled)")
    }

    // MARK: - Shop actions (host UI over the SDK store)

    /// Loads the shop through the SDK's built-in store: the catalog log comes
    /// from the SDK request (both stores), the Buy-button rows from
    /// `loadProducts()` — catalog rows joined with StoreKit products and
    /// prices (the scheme's StoreKit test configuration locally, the App
    /// Store sandbox on a real build).
    private func loadShop() async throws {
        let catalog = appClient.payments().products()
        let rows = catalog.enabled
            ? catalog.products.map { "\($0.productId)[\($0.platform)/\($0.type)]" }.sorted()
            : []
        append("payments catalog: enabled=\(catalog.enabled) rows=[\(rows.joined(separator: " "))]")
        shopRows = try await appClient.storeKitPayments().loadProducts()
        let described = shopRows.map { row in
            row.product.productId + " " + (row.displayPrice ?? "-")
        }
        append("storekit: \(shopRows.count) products \(described.joined(separator: ", "))")
    }

    /// Buys one row through the SDK's built-in store and logs the outcome.
    /// The row in hand is exactly what the user clicked — pass it as-is so
    /// the pipeline never re-looks it up against a possibly stale snapshot.
    /// The SDK ran the whole pipeline (StoreKit sheet → JWS proof → verify →
    /// finish); the sample only renders the result, like a game would.
    private func buy(_ row: Open4IDStoreProduct) async throws {
        let productId = row.product.productId
        let outcome = try await appClient.storeKitPayments().purchase(row.product)
        switch outcome.kind {
        case Open4IDPurchaseOutcome.verified:
            if let receipt = outcome.receipt {
                append("buy \(productId): verifyConsumable ok state=\(receipt.state) "
                    + "quantity=\(receipt.quantity) ref=\(receipt.transactionRef)")
            } else {
                let granted = outcome.entitlements
                    .map { "\($0.key) [\($0.state)]" }
                    .sorted()
                    .joined(separator: ", ")
                append("buy \(productId): verifyTransaction ok, "
                    + "\(outcome.entitlements.count) entitlement(s) \(granted)")
                // Re-subscribe hint: for a subscription the store account
                // already owns, Apple returns the existing transaction
                // WITHOUT a purchase sheet. An expired state means the
                // sandbox account owns a lapsed subscription (sandbox
                // 1-month ≈ 5 minutes).
                if outcome.entitlements.contains(where: { $0.state == "expired" }) {
                    append("storekit: no sheet shown — Apple's sandbox returned the "
                        + "subscription's existing (lapsed) transaction instead of the "
                        + "purchase sheet, so no new payment started. Known sandbox "
                        + "limitation; production resubscribes normally. To re-test: clear "
                        + "the sandbox tester's subscription history, or run via Xcode so "
                        + "the local StoreKit configuration applies (fresh sheet there).")
                }
            }
        case Open4IDPurchaseOutcome.pending:
            append("buy \(productId): pending (ask-to-buy)")
        default:
            append("buy \(productId): cancelled by user")
            if row.product.type == "subscription" {
                // Apple refuses a second purchase of a subscription the store
                // account still holds ("You're currently subscribed to this")
                // and surfaces it as userCancelled — no payment happens.
                append("storekit: Apple refused the second purchase — the store "
                    + "account still holds an active subscription for this product. "
                    + "It becomes re-purchasable once it lapses (sandbox 1-month ≈ "
                    + "5 minutes).")
            }
        }
    }

    /// SDK restore through the proof source the built-in store registered
    /// (`Transaction.currentEntitlements`).
    private func restorePurchases() async throws {
        let result = try await appClient.payments().restore()
        append("restore ok: verified=\(result.verified) rejected=\(result.rejected) "
            + "conflict=\(result.conflict) noProofs=\(result.proofsUnavailable)")
    }

    private func refreshEntitlements() async throws {
        let snapshot = try await appClient.entitlements().refresh()
        let list = snapshot.entitlements
            .map { "\($0.key) [state=\($0.state), src=\($0.source), "
                + "product=\($0.productId ?? "-"), expires=\($0.expiresAt ?? "-")]" }
            .sorted()
        append("entitlements: \(snapshot.entitlements.count) -> [\(list.joined(separator: " "))]")
    }
}

/// `OPEN4ID_<name>` launch-environment override with a fixture default, so a
/// local-stack or alternate-app run needs no source edit. Set values in the
/// scheme's Run → Arguments → Environment Variables.
private func envDefault(_ name: String, _ fallback: String) -> String {
    ProcessInfo.processInfo.environment["OPEN4ID_\(name)"] ?? fallback
}
