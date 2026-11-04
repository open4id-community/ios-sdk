import SwiftUI
import os
import Open4IDSDK

/// Mirrors `examples/android-sdk-minimal`: editable configuration fields,
/// the same action order (bootstrap, social row, refresh, credentials,
/// user, sign-out, delete), and an append-only log console.
struct ContentView: View {

    // MARK: - Configuration (dev fixtures; the sample bundle id
    // com.open4id.example.ios is registered on the development application)

    @State private var appId = "app_4a17c6406abaefdf0d9a705e7175b37c"
    @State private var environment = "development"
    @State private var publicSdkKey = "sdk_pk_1c91d1ee8bcf04e9226c09f291bd18c21ceeaa6f61b34203"
    @State private var endpoint = "https://id.open4id.com/api"
    /// Portal origin hosting the per-app social bridges (GitHub/Facebook/
    /// Apple callback pages). Defaults to the production Portal; override
    /// via OPEN4ID_PORTAL_ORIGIN for local development runs.
    @State private var portalOrigin =
        ProcessInfo.processInfo.environment["OPEN4ID_PORTAL_ORIGIN"] ?? "https://app.open4id.com"
    @State private var redirectUri = "com.open4id.example.ios://open4id/callback"
    @State private var bundleId = "com.open4id.example.ios"
    /// The GCP iOS-type Google OAuth client (same project as the Web
    /// client). GoogleSignIn-iOS requires it; empty keeps the typed
    /// `provider_unavailable` Google button.
    @State private var googleIosClientId =
        "240704269959-fgo38gpqj16f9ompn9kb1mcej1e4fo84.apps.googleusercontent.com"

    // MARK: - Credentials

    @State private var email = ""
    @State private var password = ""
    @State private var emailField = ""

    // MARK: - Session + log

    @State private var sessionText = "not signed in"
    @State private var logLines: [String] = ["[open4id-minimal] Ready."]
    @State private var busy = false

    // MARK: - Login UI (phase 13)

    @State private var showLoginUI = false
    @State private var authModel = Open4IDAuthViewModel()

    /// Logs the login-UI host callbacks into the shared console, mirroring
    /// the Android sample's listener wiring.
    private final class SampleAuthListener: Open4IDAuthViewModel.Listener {
        var onEvent: ((String) -> Void)?
        func onSignedIn(provider: String) {
            onEvent?("login ui: signed in provider=\(provider)")
        }
        func onSignedOut() {
            onEvent?("login ui: signed out")
        }
        func onAccountDeleted() {
            onEvent?("login ui: account deleted")
        }
    }

    @State private var authListener = SampleAuthListener()

    // MARK: - Payments (App Store)

    /// StoreKit 2 bridge (purchases, prices, proof source) owned by the
    /// sample like the Android sample owns Play Billing.
    @StateObject private var storeKit = Open4IDStoreKitBridge()
    /// The app_store rows of the Open4ID catalog, one Buy button each.
    @State private var appStoreProducts: [PaymentProduct] = []

    /// Console mirror for automated verification (simulator unified log:
    /// `subsystem == "com.open4id.example.ios"`).
    private let console = Logger(subsystem: "com.open4id.example.ios",
                                 category: "minimal")

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    field("App ID", $appId)
                    field("Environment", $environment)
                    field("Public SDK key", $publicSdkKey)
                    field("Endpoint", $endpoint)
                    field("Portal origin", $portalOrigin)
                    field("Redirect URI", $redirectUri)
                    field("Bundle ID", $bundleId)
                    field("Google iOS client ID", $googleIosClientId)
                }

                Section("Bootstrap") {
                    Button("Load bootstrap") { run(loadBootstrap) }
                }

                Section("Social") {
                    Button("Sign in with Google") { run(signInGoogle) }
                    Button("Continue as guest") { run(continueAsGuest) }
                    Button("Sign in with GitHub") { run(signInGitHub) }
                    Button("Sign in with Facebook") { run(signInFacebook) }
                    Button("Sign in with Apple") { run(signInApple) }
                }

                Section("Session") {
                    Button("Refresh session") { run(refreshSession) }
                    LabeledContent("Session", value: sessionText)
                    Button("Sign out") { run(signOut) }
                    Button("Delete account", role: .destructive) { run(deleteAccount) }
                }

                Section("Email / password") {
                    field("Email", $email)
                    SecureField("Password", text: $password)
                    Button("Sign in") { run(signInPassword) }
                    field("Email", $emailField)
                    HStack {
                        Button("Register") { run(register) }
                        Button("Forgot password") { run(requestReset) }
                    }
                }

                Section("Account") {
                    Button("Get user") { run(getUser) }
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

                Section("Login UI") {
                    Button("Open login dialog") {
                        prepareLoginUI()
                        showLoginUI = true
                    }
                    LabeledContent("Locale", value: "en")
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
                    .frame(minHeight: 180)
                }
            }
            .navigationTitle("Open4ID Minimal")
            .disabled(busy)
            .open4IDLoginSheet(isPresented: $showLoginUI, model: authModel)
        }
        .onAppear {
            authListener.onEvent = { line in
                append(line)
                if line.contains("signed in provider=") {
                    if let session = appClient.getSession() {
                        sessionText = "sub=\(session.userId) scope=\(session.scope)"
                    }
                } else if line.contains("signed out") || line.contains("account deleted") {
                    sessionText = "not signed in"
                }
            }
            authModel.addListener(authListener)
            // The GitHub/Apple web sessions present from the first scene window.
            appClient.setPresentationAnchor {
                UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                    .first
            }
            // Auto configure + bootstrap on launch (same behavior as the
            // sibling minimal samples) so a device/simulator launch proves
            // the live path in the console without tapping anything.
            Task {
                do {
                    try configureClient()
                    // Bind the SDK's restore proof source once: the
                    // payments namespace object is stable for the client's
                    // lifetime, so this registration sticks.
                    appClient.payments().proofSource = storeKit.proofSource
                    let bootstrap = try await appClient.bootstrap()
                    append("bootstrap ok: app=\(bootstrap.displayName ?? bootstrap.appId) "
                        + "google=\(bootstrap.login.google.enabled)")
                    // The login-UI model tracks this bootstrap + client.
                    authModel.setBootstrap(bootstrap)
                    // Phase-12 posture row: the App Attest probe is audit-only.
                    let report = await Attestation.collect()
                    append("attestation: \(report.verdict.rawValue) (\(report.reason ?? "-"))")
                    // Debug hook for automated verification: launch with
                    // SIMCTL_CHILD_OPEN4ID_AUTOTEST=github|facebook|apple to
                    // auto-run one web flow, or =payments to auto-run the
                    // payment rehearsal (catalog + StoreKit products +
                    // purchase of the first one_time row; the StoreKit sheet
                    // needs the human's confirm in DeviceHub).
                    if let autotest = ProcessInfo.processInfo.environment["OPEN4ID_AUTOTEST"] {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        if autotest == "github" {
                            try await signInGitHub()
                        } else if autotest == "facebook" {
                            try await signInFacebook()
                        } else if autotest == "apple" {
                            try await signInApple()
                        } else if autotest == "github-ephemeral" {
                            appClient.setPrefersEphemeralWebSessions(true)
                            try await signInGitHub()
                        } else if autotest == "payments" {
                            try await loadPaymentsCatalog()
                            try await Task.sleep(nanoseconds: 10_000_000_000)
                            if let product = appStoreProducts.first {
                                append("autotest: buying \(product.productId)")
                                append(await storeKit.purchase(product, client: appClient))
                            }
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
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
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

    /// Typed-error detail for the log console: stable key plus field errors
    /// (e.g. `popup_blocked ["presentationAnchor": "required"]`), so a
    /// failure names its exact gate.
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
        if let social = appClient as? Open4IDSocialClient {
            social.setGoogleIosClientId(googleIosClientId)
        }
        try appClient.configure(appId: appId,
                                environment: environment,
                                publicSdkKey: publicSdkKey,
                                endpoint: endpoint,
                                redirectUri: redirectUri,
                                bundleId: bundleId)
        // Never resets session state, so this is safe on every configure.
        try appClient.setPortalOrigin(portalOrigin)
    }

    /// Binds the login-UI view model to the current client + bootstrap
    /// before the dialog opens (Android `setAuthClient` + `setBootstrap`).
    private func prepareLoginUI() {
        authModel.setLocale("en")
        authModel.appName = nil
        authModel.githubCallbackUri = nil
        authModel.facebookCallbackUri = nil
        authModel.appleReturnUri = nil
        authModel.setAuthClient(appClient)
        authModel.setBootstrap(appClient.getBootstrap())
        authModel.setMode(.signIn)
    }

    private func append(_ line: String) {
        logLines.append(line)
        print("[open4id-minimal] \(line)")
        console.notice("open4id-minimal: \(line, privacy: .public)")
        persistLog()
    }

    /// Mirrors the log console into Documents/open4id-log.txt so a device
    /// session can be inspected afterwards via
    /// `devicectl device copy from --domain-type appDataContainer`.
    private func persistLog() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("open4id-log.txt")
        try? logLines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func showSession(_ session: AuthSession) {
        sessionText = "sub=\(session.userId) scope=\(session.scope)"
        append("signed in: sub=\(session.userId)")
    }

    private func loadBootstrap() async throws {
        let bootstrap = try await appClient.bootstrap()
        append("bootstrap ok: app=\(bootstrap.displayName ?? bootstrap.appId) "
            + "google=\(bootstrap.login.google.enabled)")
    }

    private func signInGoogle() async throws {
        let session = try await appClient.signInWithGoogle()
        showSession(session)
    }

    private func continueAsGuest() async throws {
        let session = try await appClient.continueAsGuest()
        sessionText = "sub=\(session.userId) scope=\(session.scope)"
        append("guest ok: sub=\(session.userId) scope=\(session.scope)")
    }

    private func signInGitHub() async throws {
        let session = try await appClient.signInWithGitHub()
        showSession(session)
    }

    private func signInFacebook() async throws {
        let session = try await appClient.signInWithFacebook()
        showSession(session)
    }

    private func signInApple() async throws {
        let session = try await appClient.signInWithApple()
        showSession(session)
    }

    private func refreshSession() async throws {
        let session = try await appClient.refresh()
        append("refresh ok: sub=\(session.userId)")
    }

    private func signInPassword() async throws {
        let session = try await appClient.signInWithPassword(email: email, password: password)
        showSession(session)
    }

    private func register() async throws {
        try await appClient.register(email: emailField, password: password)
        append("register ok: verification email sent (generic response)")
    }

    private func requestReset() async throws {
        try await appClient.requestPasswordReset(email: emailField)
        append("reset email requested (generic response)")
    }

    private func getUser() async throws {
        let user = try await appClient.getUser()
        append("user: sub=\(user.sub)"
            + (user.email.map { " email=\($0)" } ?? "")
            + " verified=\(user.emailVerified)")
    }

    private func signOut() async throws {
        try await appClient.signOut()
        sessionText = "not signed in"
        append("signed out")
    }

    private func deleteAccount() async throws {
        try await appClient.deleteAccount()
        sessionText = "not signed in"
        append("account deleted")
    }

    // MARK: - Payments actions

    /// Syncs the Buy-button list from the bootstrap payment catalog and
    /// logs the full catalog (both stores) Android-sample style.
    private func loadPaymentsCatalog() async throws {
        let catalog = appClient.payments().products()
        let rows = catalog.enabled
            ? catalog.products.map { "\($0.productId)[\($0.platform)/\($0.type)]" }.sorted()
            : []
        append("payments catalog: enabled=\(catalog.enabled) rows=[\(rows.joined(separator: " "))]")
        appStoreProducts = catalog.forPlatform(PaymentProvider.appStore)
        try await loadStoreKitProducts()
    }

    /// Resolves StoreKit prices for the catalog rows (simulator: the scheme's
    /// StoreKit configuration; device: the App Store sandbox).
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
