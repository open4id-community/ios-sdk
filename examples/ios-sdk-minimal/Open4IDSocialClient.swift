import Foundation
import GoogleSignIn
import UIKit
import Open4IDSDK

/// Sample-only host override mirroring the Android sample's
/// `SocialAuthClient`: interactive Google Sign-In only.
///
/// The base SDK owns GitHub and Apple (`ASWebAuthenticationSession`
/// defaults) and reports `provider_unavailable` for Google — iOS has no
/// Play-Services analogue, so hosts override
/// `getGoogleAuthorizationCode(clientId:timeoutMs:)` with their own code
/// acquisition. This sample uses the Google Sign-In SDK
/// (`GoogleSignIn-iOS` SPM package) exactly like the Android sample uses
/// `play-services-auth`: a forced sign-out so the account picker always
/// appears, then a presented sign-in whose result carries a fresh server
/// auth code.
///
/// Two Google client IDs are involved:
/// - `serverClientID` = the bootstrap Web client (`clientId` argument) —
///   the server-auth-code audience, exchanged server-side through the
///   empty-`redirect_uri` fallback (2026-10-12 server fix, Android parity).
/// - `clientID` = the GCP **iOS-type** OAuth client bound to the sample
///   bundle `com.open4id.example.ios`, set via `setGoogleIosClientId(_:)`
///   from the sample config. GoogleSignIn-iOS refuses to run without it
///   (an empty value keeps the typed `provider_unavailable` behavior of
///   the base seam so the button stays honest in the UI).
///
/// Typed errors mirror the Android table: user cancel → `popup_closed`,
/// timeout budget → `popup_timeout`, missing code → `access_denied`,
/// configuration gaps → `provider_unavailable` / `invalid_request`.
final class Open4IDSocialClient: Open4IDAuthClient {

    /// The GCP iOS-type OAuth client ID (dev fixture; registered for the
    /// sample bundle ID). Empty keeps the base seam's `provider_unavailable`.
    private(set) var googleIosClientId = ""

    func setGoogleIosClientId(_ value: String) {
        googleIosClientId = value.trimmingCharacters(in: .whitespaces)
    }

    override func getGoogleAuthorizationCode(clientId: String,
                                             timeoutMs: Int) async throws -> String {
        let budgetMs = timeoutMs > 0 ? timeoutMs : 120_000
        if googleIosClientId.isEmpty {
            throw SdkValidationError(key: "client.auth.provider_unavailable",
                                     fieldErrors: ["google_ios_client_id": "required"])
        }
        guard let window = await MainActor.run(body: { Self.topWindow() }),
              let presenting = await MainActor.run(body: {
                  Self.presentingController(from: window)
              }) else {
            throw SdkValidationError(key: "client.auth.invalid_request",
                                     fieldErrors: ["window": "required"])
        }
        // Picker + fresh server auth code every time (Android parity: a
        // best-effort sign-out precedes every interactive sign-in).
        GIDSignIn.sharedInstance.signOut()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: googleIosClientId,
            serverClientID: clientId)

        return try await Self.raceSignInTimeout(budgetMs: budgetMs,
                                                presenting: presenting)
    }

    // MARK: - Pieces

    private static func topWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
    }

    private static func presentingController(from window: UIWindow) -> UIViewController? {
        // The topmost presented controller if one exists, else the window's
        // root controller. Nil only when the scene has no root (not a case
        // for this sample).
        var controller: UIViewController? = window.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    /// Runs the presented Google sign-in inside the interaction budget:
    /// the first of (sign-in result, timeout) settles the flow, and the
    /// loser is cancelled — the same continuation-boxed race the SDK uses
    /// for its web sessions.
    private static func raceSignInTimeout(budgetMs: Int,
                                          presenting: UIViewController) async throws -> String {
        let budgetNs = UInt64(budgetMs) * 1_000_000
        return try await withThrowingTaskGroup(of: String.self) { group -> String in
            group.addTask {
                try await Self.performSignIn(presenting: presenting)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: budgetNs)
                throw SdkAuthError(key: "client.auth.popup_timeout")
            }
            let first = try await group.next() ?? ""
            group.cancelAll()
            return first
        }
    }

    /// The presented sign-in itself. `signIn` must run on the main actor;
    /// awaiting this `@MainActor` helper from the race task hops correctly.
    /// Type mapping mirrors the Android sample: user cancel →
    /// `popup_closed`, everything else programmatic → `access_denied`.
    @MainActor
    private static func performSignIn(presenting: UIViewController) async throws -> String {
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenting)
            guard let code = result.serverAuthCode, !code.isEmpty else {
                throw SdkAuthError(key: "client.auth.access_denied")
            }
            return code
        } catch let error as NSError
        where error.code == -5 { // GIDSignInErrorCode.kCanceled (-5): user cancel
            throw SdkAuthError(key: "client.auth.popup_closed")
        } catch {
            var fields = ["reason": "google_sign_in_failed"]
            if let ns = error as? NSError {
                fields["gid_domain"] = ns.domain
                fields["gid_code"] = String(ns.code)
                if let message = ns.userInfo[NSLocalizedDescriptionKey] as? String,
                   !message.isEmpty {
                    fields["gid_message"] = message
                }
            }
            throw SdkValidationError(key: "client.auth.access_denied",
                                     fieldErrors: fields)
        }
    }
}
