import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var isEligibleForTrial = false
    @State private var isShowingOfferCodeRedemption = false
    @State private var selectedProductID = SubscriptionManager.monthlyProductID

    private let features: [(icon: String, title: String)] = [
        ("play.rectangle.fill", "Video Playback Mode"),
        ("phone.fill", "Fake Call Mode"),
        ("textformat", "LED Banner Mode"),
        ("coloncurrencysign.circle.fill", "Currency Converter Mode"),
        ("location.north.circle.fill", "Travel Dashboard Mode"),
        ("bird.fill", "Flappy Bird Mode"),
        ("bitcoinsign.circle.fill", "Bitcoin Price Mode"),
        ("plus.forwardslash.minus", "Calculator Mode"),
        ("eye.slash.fill", "Ad-Free Video Exports"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.yellow)

                        Text("TravelVid Premium")
                            .font(.title.bold())

                        Text("Unlock every premium recording mode")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Includes Travel Dashboard, Fake Call, Bitcoin, LED Banner, Currency Converter, and more.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Premium Mode Previews")
                            .font(.headline)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                PremiumPreviewCard(title: "Fake Call") {
                                    FakeCallingView(contactName: "Airport Pickup")
                                }

                                PremiumPreviewCard(title: "LED Banner") {
                                    LEDBannerView(
                                        text: "WELCOME TO SAIGON",
                                        useNasalization: true,
                                        speed: 40,
                                        isPreview: true
                                    )
                                }

                                PremiumPreviewCard(title: "Currency Converter") {
                                    PremiumCurrencyPreview()
                                }

                                PremiumPreviewCard(title: "Travel Dashboard") {
                                    TravelDashboardView(
                                        speedUnit: .mph,
                                        audioLevelDB: nil,
                                        audioEnabled: true,
                                        isPreview: true
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Feature list
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(features, id: \.title) { feature in
                            HStack(spacing: 14) {
                                Image(systemName: feature.icon)
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                                    .frame(width: 28, alignment: .center)
                                Text(feature.title)
                                    .font(.body)
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    // Purchase options
                    if subscriptionManager.isLoadingProducts {
                        ProgressView("Loading purchase options...")
                            .padding()
                    } else if !subscriptionManager.products.isEmpty {
                        VStack(spacing: 12) {
                            if let monthlyProduct = subscriptionManager.monthlyProduct {
                                purchaseOptionCard(
                                    product: monthlyProduct,
                                    title: "Monthly",
                                    detail: isEligibleForTrial
                                        ? "2 weeks free, then \(monthlyProduct.displayPrice) per month"
                                        : "\(monthlyProduct.displayPrice) per month, cancel anytime",
                                    badge: isEligibleForTrial ? "FREE TRIAL" : nil
                                )
                            }

                            if let lifetimeProduct = subscriptionManager.lifetimeProduct {
                                purchaseOptionCard(
                                    product: lifetimeProduct,
                                    title: "Lifetime",
                                    detail: "One-time purchase. No subscription.",
                                    badge: "BEST VALUE"
                                )
                            }

                            Text("Premium also removes interstitial ads before exports and preview opens.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            if selectedProductID == SubscriptionManager.lifetimeProductID {
                                Text("Already subscribed monthly? Buying Lifetime does not automatically cancel your subscription. Cancel monthly billing in Apple Account Settings after your Lifetime purchase is complete.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text("Unable to load purchase options")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Tap to Retry") {
                                Task { await loadProductsAndSelectDefault() }
                            }
                            .font(.subheadline.bold())
                        }
                        .padding()
                    }

                    // Subscribe button
                    Button {
                        isPurchasing = true
                        Task {
                            await loadProductsAndSelectDefault()

                            guard let product = selectedProduct else {
                                subscriptionManager.purchaseError = "The selected Premium option is not available. Please try again."
                                showError = true
                                isPurchasing = false
                                return
                            }

                            let purchaseSucceeded = await subscriptionManager.purchase(product)
                            isPurchasing = false
                            if purchaseSucceeded {
                                dismiss()
                            }
                            if subscriptionManager.purchaseError != nil {
                                showError = true
                            }
                        }
                    } label: {
                        Group {
                            if isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(purchaseButtonTitle)
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background((selectedProduct == nil || isPurchasing) ? Color.gray : Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                    }
                    .disabled(selectedProduct == nil || isPurchasing)
                    .padding(.horizontal)

                    Button("Redeem Offer Code") {
                        isShowingOfferCodeRedemption = true
                    }
                    .buttonStyle(.bordered)

                    // Restore
                    Button("Restore Purchases") {
                        Task {
                            await subscriptionManager.restorePurchases()
                            if subscriptionManager.isPremium {
                                dismiss()
                            }
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    // Legal links (required for auto-renewable subscriptions)
                    VStack(spacing: 8) {
                        Text("Monthly renews automatically until canceled. Lifetime is a one-time purchase.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 16) {
                            Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                            Text("·").foregroundStyle(.secondary)
                            Link("Privacy Policy", destination: URL(string: "https://jimwashkau.com/privacy-policy-2/")!)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Purchase Error", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    subscriptionManager.purchaseError = nil
                }
            } message: {
                Text(subscriptionManager.purchaseError ?? "An unknown error occurred.")
            }
            .offerCodeRedemption(isPresented: $isShowingOfferCodeRedemption) { result in
                switch result {
                case .success:
                    Task {
                        await subscriptionManager.refreshAfterOfferCodeRedemption()
                        if subscriptionManager.isPremium {
                            dismiss()
                        } else if subscriptionManager.purchaseError != nil {
                            showError = true
                        }
                    }
                case .failure(let error):
                    subscriptionManager.purchaseError = "Offer code redemption failed: \(error.localizedDescription)"
                    showError = true
                }
            }
            .task {
                await loadProductsAndSelectDefault()
                isEligibleForTrial = await subscriptionManager.isEligibleForIntroOffer()
            }
        }
    }

    private var selectedProduct: Product? {
        subscriptionManager.products.first { $0.id == selectedProductID }
    }

    private var purchaseButtonTitle: String {
        guard let selectedProduct else { return "Choose a Premium Option" }

        if selectedProduct.id == SubscriptionManager.lifetimeProductID {
            return "Unlock Lifetime — \(selectedProduct.displayPrice)"
        }

        if isEligibleForTrial {
            return "Start Free Trial"
        }

        return "Subscribe — \(selectedProduct.displayPrice) / month"
    }

    @MainActor
    private func loadProductsAndSelectDefault() async {
        if subscriptionManager.products.isEmpty {
            await subscriptionManager.loadProducts()
        }

        if selectedProduct == nil {
            selectedProductID = subscriptionManager.monthlyProduct?.id
                ?? subscriptionManager.lifetimeProduct?.id
                ?? SubscriptionManager.monthlyProductID
        }
    }

    private func purchaseOptionCard(
        product: Product,
        title: String,
        detail: String,
        badge: String?
    ) -> some View {
        let isSelected = selectedProductID == product.id

        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(title == "Lifetime" ? Color.white : Color.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(title == "Lifetime" ? Color.blue : Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.10) : Color(uiColor: .secondarySystemBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

private struct PremiumPreviewCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
                .frame(width: 190, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct PremiumCurrencyPreview: View {
    @State private var amount = "100"
    @State private var base: CurrencyConverterBase = .usdToVnd

    var body: some View {
        CurrencyConverterView(amountText: $amount, base: $base, isPreview: true)
    }
}
