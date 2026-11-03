import Foundation
import StoreKit
import Open4IDSDK

/// StoreKit 2 wiring for the sample's **Payments (App Store)** section,
/// mirroring the Android sample's `PlayBillingHelper`: the SDK keeps zero
/// store dependency, so the sample owns the store client.
///
/// Details that matter for the Core API contract:
///
/// - The server verifies the StoreKit 2 JWS (`jwsRepresentation`), so the
///   bridge passes it through `TransactionProof.appStore` unmodified.
/// - One-time products verify through `payments().verifyTransaction`
///   (entitlement publish); consumables through `payments().verifyConsumable`
///   (ledger delivery receipt), chosen by the catalog row's type — the same
///   rule the Android sample follows.
/// - The host owns `Transaction.finish()` (the SDK never calls it), so the
///   bridge finishes *after* a successful verify.
/// - `restore` uses the SDK's registered `PaymentProofSource`; the bridge
///   supplies proofs out of `Transaction.currentEntitlements`, which by
///   definition excludes consumables — consumables re-deliver through
///   `verifyConsumable`, never through the entitlement snapshot.
@MainActor
final class Open4IDStoreKitBridge: ObservableObject {

    /// StoreKit products resolved from the local StoreKit configuration
    /// (simulator) or the App Store sandbox (device), keyed by product id.
    @Published private(set) var prices: [String: String] = [:]
    @Published private(set) var storeProductsLoaded = 0

    /// SDK-facing proof source for `payments().restore()`.
    let proofSource = StoreKitProofSource()

    private var storeProducts: [String: Product] = [:]

    /// Loads the StoreKit products for the app_store rows of the Open4ID
    /// catalog. With the scheme's StoreKit configuration active, all three
    /// dev rows (`pkg_01`–`pkg_03`) resolve.
    func loadStoreProducts(for catalog: [PaymentProduct]) async -> String {
        let ids = catalog.map(\.productId)
        do {
            let storeProducts = try await Product.products(for: ids)
            var prices: [String: String] = [:]
            for product in storeProducts {
                self.storeProducts[product.id] = product
                prices[product.id] = product.displayPrice
            }
            self.prices = prices
            storeProductsLoaded = storeProducts.count
            if storeProducts.isEmpty {
                return "storekit: 0 products for [\(ids.joined(separator: ", "))] "
                    + "(StoreKit test configuration not active?)"
            }
            return "storekit: \(storeProducts.count) products "
                + storeProducts.map { "\($0.id) \($0.displayPrice)" }
                    .sorted().joined(separator: ", ")
        } catch {
            storeProductsLoaded = 0
            return "storekit products failed: \(Self.describe(error))"
        }
    }

    /// Purchases one catalog row: StoreKit sheet → JWS proof → Open4ID
    /// verify (entitlements for one_time/subscription, delivery receipt for
    /// consumable) → `finish()`. The returned line is log-console text.
    func purchase(_ product: PaymentProduct, client: Open4IDAuthClient) async -> String {
        let surface = client.payments()
        let productId = product.productId
        guard let storeProduct = storeProducts[productId] else {
            return "buy \(productId): no StoreKit product — load products first"
        }
        do {
            switch try await storeProduct.purchase() {
            case .success(let verification):
                let transaction: Transaction
                let jws: String
                switch verification {
                case .verified(let t):
                    transaction = t
                    // The signed JWS lives on the VerificationResult, not on
                    // the decoded Transaction.
                    jws = verification.jwsRepresentation
                case .unverified(_, let error):
                    return "buy \(productId): StoreKit verification of the JWS failed "
                        + "locally (\(error.localizedDescription))"
                }
                let proof = try TransactionProof.appStore(
                    productId: transaction.productID,
                    jwsRepresentation: jws)
                if product.isConsumable {
                    let receipt = try await surface.verifyConsumable(proof)
                    await transaction.finish()
                    return "buy \(productId): verifyConsumable ok state=\(receipt.state) "
                        + "quantity=\(receipt.quantity) ref=\(receipt.transactionRef)"
                } else {
                    let granted = try await surface.verifyTransaction(proof)
                    await transaction.finish()
                    return "buy \(productId): verifyTransaction ok, "
                        + "\(granted.count) entitlement(s) "
                        + granted.map { "\($0.key) [\($0.state)]" }
                            .sorted().joined(separator: ", ")
                }
            case .pending:
                return "buy \(productId): pending (ask-to-buy)"
            case .userCancelled:
                return "buy \(productId): cancelled by user"
            @unknown default:
                return "buy \(productId): unknown purchase result"
            }
        } catch {
            return "buy \(productId): failed → \(Self.detail(error))"
        }
    }

    private static func describe(_ error: Error) -> String {
        if let storeKitError = error as? StoreKitError {
            return "storekit \(storeKitError)"
        }
        return detail(error)
    }

    /// Same typed-error rendering as the sample console: stable key plus
    /// field errors; the proof value never reaches the string.
    private static func detail(_ error: Error) -> String {
        var text = "\(error)"
        if let fields = (error as? SdkError)?.errorUserInfo["field_errors"]
            as? [String: String], !fields.isEmpty {
            text += " \(fields)"
        }
        return text
    }
}

/// SDK `PaymentProofSource` over StoreKit 2: every verified
/// `currentEntitlements` row becomes an App Store proof. Consumables are
/// absent by construction (they are not entitlements).
final class StoreKitProofSource: PaymentProofSource {

    func collectProofs(_ completion: @escaping ([TransactionProof], Error?) -> Void) {
        Task { @MainActor in
            var proofs: [TransactionProof] = []
            var failure: Error?
            do {
                for await verification in Transaction.currentEntitlements {
                    if case .verified(let transaction) = verification {
                        proofs.append(try TransactionProof.appStore(
                            productId: transaction.productID,
                            jwsRepresentation: verification.jwsRepresentation))
                    }
                }
            } catch {
                failure = error
            }
            completion(proofs, failure)
        }
    }
}
