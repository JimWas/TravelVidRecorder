import StoreKit

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    static let monthlyProductID = "com.jimwas.travelvid.premium"
    static let lifetimeProductID = "com.jimwas.travelvid.premium.lifetime"

    @Published private(set) var isPremium: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts: Bool = false
    @Published var purchaseError: String?

    private let premiumProductIDs: Set<String> = [
        SubscriptionManager.monthlyProductID,
        SubscriptionManager.lifetimeProductID,
    ]
    private var transactionListener: Task<Void, Error>?

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == Self.lifetimeProductID }
    }

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
        UserDefaults.standard.set(isPremium, forKey: "isPremium")
        print("🧪 Test toggle: isPremium = \(isPremium)")
        #endif
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoadingProducts = true
        purchaseError = nil
        do {
            let loadedProducts = try await Product.products(for: premiumProductIDs)
            products = loadedProducts.sorted { lhs, rhs in
                if lhs.id == Self.monthlyProductID { return true }
                if rhs.id == Self.monthlyProductID { return false }
                return lhs.displayName < rhs.displayName
            }
            if products.isEmpty {
                print("StoreKit: No Premium products returned for IDs \(premiumProductIDs.sorted()). Check App Store Connect configuration.")
                purchaseError = "Premium purchase options are not available. Please check your connection and try again."
            } else {
                purchaseError = nil
            }
        } catch {
            print("StoreKit: Failed to load products: \(error)")
            purchaseError = "Could not load Premium purchase options. Please check your connection and try again."
        }
        isLoadingProducts = false
    }

    // MARK: - Introductory Offer Eligibility

    func isEligibleForIntroOffer() async -> Bool {
        guard let product = monthlyProduct else { return false }
        guard let subscription = product.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard premiumProductIDs.contains(product.id) else {
            purchaseError = "This Premium purchase option is not recognized."
            return false
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateSubscriptionStatus()
                purchaseError = nil
                return true

            case .userCancelled:
                purchaseError = nil
                return false

            case .pending:
                purchaseError = "Purchase is pending approval."
                return false

            @unknown default:
                return false
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            purchaseError = nil
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    func refreshAfterOfferCodeRedemption() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            purchaseError = nil
        } catch {
            purchaseError = "Code redemption refresh failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Subscription Status

    func updateSubscriptionStatus() async {
        var hasPremiumEntitlement = false

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               premiumProductIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                hasPremiumEntitlement = true
                break
            }
        }

        isPremium = hasPremiumEntitlement
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
