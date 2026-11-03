import SwiftUI
import os
import Open4IDSDK

/// Minimal **macOS App Store IAP test harness** for the Open4ID SDK.
///
/// Scope is deliberately narrow: **payments only, no login UI**. It owns a
/// StoreKit 2 bridge (`Open4IDStoreKitBridge.swift`) and the same Open4ID IAP
/// catalog as `examples/ios-sdk-minimal` (`Open4IDStoreConfig.storekit`), then
/// verifies StoreKit 2 JWS proofs through the SDK's headless payments API.
///
/// There is no social/provider/browser flow here, so no `ASWebAuthentication`
/// anchor, URL-scheme callback, or Portal origin is needed. The SDK still
/// requires a `redirectUri` at `configure` time; it is a placeholder that the
/// IAP path never uses. A purchase that has no session signs in as a guest
/// automatically (`payments().verifyTransaction` / `verifyConsumable`), which
/// requires guest login to be enabled for the application.
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

    // MARK: - Payments (App Store)

    /// StoreKit 2 bridge (purchases, prices, proof source) owned by the
    /// sample. StoreKit 2 is the same framework on macOS, so the bridge is
    /// reused verbatim from the iOS sample.
    @StateObject private var storeKit = Open4IDStoreKitBridge()
    /// The `app_store` rows of the Open4ID catalog, one Buy button each.
    @State private var appStoreProducts: [PaymentProduct] = []

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
                    Button("Load payments catalog") { run(loadPaymentsCatalog) }
                    ForEach(appStoreProducts, id: \.productId) { product in
                        Button("Buy \(product.productId) [\(product.type)]"
                               + (storeKit.prices[product.productId].map { " \($0)" } ?? "")) {
                            run { _ = await storeKit.purchase(product, client: appClient) }
                        }
                    }
                    Button("Reload StoreKit products") { run(loadStoreKitProducts) }
                    Button("Restore purchases") { run(restorePurchases) }
                    Button("Entitlements (ledger)") { run(refreshEntitlements) }
                    LabeledContent("StoreKit", value: "\(storeKit.storeProductsLoaded) products")
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
            // Auto configure + bootstrap on launch so a launch proves the
            // live path in the console without tapping anything. Bootstrap is
            // what loads the payment catalog and enables the guest session
            // the first purchase needs.
            Task {
                do {
                    try configureClient()
                    // Bind the SDK's restore proof source once: the payments
                    // namespace object is stable for the client's lifetime, so
                    // this registration sticks.
                    appClient.payments().proofSource = storeKit.proofSource
                    let bootstrap = try await appClient.bootstrap()
                    bootstrapApp = bootstrap.displayName ?? bootstrap.appId
                    append("bootstrap ok: app=\(bootstrapApp) "
                        + "payments=\(bootstrap.payments.enabled)")
                    // Debug hook for automated verification: launch with
                    // OPEN4ID_AUTOTEST=payments to auto-run the rehearsal
                    // (catalog + StoreKit products + purchase of the first
                    // one-time row; the StoreKit sheet needs the human's
                    // confirm).
                    if ProcessInfo.processInfo.environment["OPEN4ID_AUTOTEST"] == "payments" {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        try await loadPaymentsCatalog()
                        try await Task.sleep(nanoseconds: 10_000_000_000)
                        if let product = appStoreProducts.first {
                            append("autotest: buying \(product.productId)")
                            append(await storeKit.purchase(product, client: appClient))
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

    // MARK: - Payments actions

    /// Syncs the Buy-button list from the bootstrap payment catalog and logs
    /// the full catalog (both stores).
    private func loadPaymentsCatalog() async throws {
        let catalog = appClient.payments().products()
        let rows = catalog.enabled
            ? catalog.products.map { "\($0.productId)[\($0.platform)/\($0.type)]" }.sorted()
            : []
        append("payments catalog: enabled=\(catalog.enabled) rows=[\(rows.joined(separator: " "))]")
        appStoreProducts = catalog.forPlatform(PaymentProvider.appStore)
        try await loadStoreKitProducts()
    }

    /// Resolves StoreKit prices for the catalog rows (the scheme's StoreKit
    /// configuration locally; the App Store sandbox with a real product).
    private func loadStoreKitProducts() async throws {
        let catalog = appStoreProducts
        let line = await storeKit.loadStoreProducts(for: catalog)
        append(line)
    }

    /// SDK restore through the registered proof source
    /// (`Transaction.currentEntitlements`).
    private func restorePurchases() async throws {
        let surface = appClient.payments()
        let result = try await surface.restore()
        append("restore ok: verified=\(result.verified) rejected=\(result.rejected) "
            + "conflict=\(result.conflict) noProofs=\(result.proofsUnavailable)")
    }

    private func refreshEntitlements() async throws {
        let snapshot = try await appClient.entitlements().refresh()
        let list = snapshot.entitlements
            .map { "\($0.key) [state=\($0.state), src=\($0.source), "
                + "product=\($0.productId ?? "-")]" }.sorted()
        append("entitlements: \(snapshot.entitlements.count) -> [\(list.joined(separator: " "))]")
    }
}

/// `OPEN4ID_<name>` launch-environment override with a fixture default, so a
/// local-stack or alternate-app run needs no source edit. Set values in the
/// scheme's Run → Arguments → Environment Variables.
private func envDefault(_ name: String, _ fallback: String) -> String {
    ProcessInfo.processInfo.environment["OPEN4ID_\(name)"] ?? fallback
}
