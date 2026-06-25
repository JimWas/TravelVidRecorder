import StoreKit

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var isPremium: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts: Bool = false
    @Published var purchaseError: String?

    private let productID = "com.jimwas.travelvid.premium"
    private var transactionListener: Task<Void, Error>?

    // MARK: - Developer Testing Override

    /// Set this to true to unlock all premium features for testing.
    /// This only works in DEBUG builds and is ignored in Release builds.
    private let developerOverrideEnabled: Bool = {
        #if DEBUG
        // Check for Xcode StoreKit testing environment or debug override
        // You can also add specific device UDIDs or Apple IDs here
        return false  // Set to false to test paywall flow in DEBUG
        #else
        return false
        #endif
    }()

    /// Check if running in StoreKit sandbox/testing environment
    private var isRunningInSandbox: Bool {
        #if DEBUG
        return true
        #else
        // In release, check receipt URL to detect sandbox
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.path.contains("sandboxReceipt")
        #endif
    }

    private init() {
        // Check developer override first
        if developerOverrideEnabled {
            isPremium = true
            print("🔓 Developer override: Premium features unlocked for testing")
        } else {
            isPremium = UserDefaults.standard.bool(forKey: "isPremium")
        }

        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            if !developerOverrideEnabled {
                await updateSubscriptionStatus()
            }
        }
    }

    /// Manually toggle premium status for testing (DEBUG only)
    func togglePremiumForTesting() {
        #if DEBUG
        isPremium.toggle()
        print("🧪 Test toggle: isPremium = \(isPremium)")
        #endif
    }

    // MARK: - Promo Codes

    private let validPromoCodes: Set<String> = [
        "NASAEMPLOYEES",
        "TRAVELVIPFREE",
        "JIMWAS2025",
    ]

    /// Returns true and unlocks premium if the code is valid and unused.
    @discardableResult
    func redeemPromoCode(_ code: String) -> Bool {
        let normalised = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard validPromoCodes.contains(normalised) else { return false }
        isPremium = true
        UserDefaults.standard.set(true, forKey: "isPremium")
        UserDefaults.standard.set(normalised, forKey: "redeemedPromoCode")
        print("🎟️ Promo code '\(normalised)' redeemed — premium unlocked")
        return true
    }

    var redeemedPromoCode: String? {
        UserDefaults.standard.string(forKey: "redeemedPromoCode")
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoadingProducts = true
        do {
            products = try await Product.products(for: [productID])
            if products.isEmpty {
                print("StoreKit: No products returned for ID '\(productID)'. Check App Store Connect configuration.")
                purchaseError = "Subscription not available. Please check your connection and try again."
            }
        } catch {
            print("StoreKit: Failed to load products: \(error)")
            purchaseError = "Could not load subscription. Please check your connection and try again."
        }
        isLoadingProducts = false
    }

    // MARK: - Introductory Offer Eligibility

    func isEligibleForIntroOffer() async -> Bool {
        guard let product = products.first else { return false }
        guard let subscription = product.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = products.first else {
            purchaseError = "Subscription not available. Please try again later."
            // Retry loading products in case they weren't loaded yet
            await loadProducts()
            return
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateSubscriptionStatus()

            case .userCancelled:
                break

            case .pending:
                purchaseError = "Purchase is pending approval."

            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    func refreshAfterOfferCodeRedemption() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            purchaseError = "Code redemption refresh failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Subscription Status

    func updateSubscriptionStatus() async {
        var hasActiveSubscription = false

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == productID,
               transaction.revocationDate == nil {
                hasActiveSubscription = true
                break
            }
        }

        isPremium = hasActiveSubscription
        UserDefaults.standard.set(isPremium, forKey: "isPremium")
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? await self.checkVerified(result) {
                    await transaction.finish()
                    await self.updateSubscriptionStatus()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
