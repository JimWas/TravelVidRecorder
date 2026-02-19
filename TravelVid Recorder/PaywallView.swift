import SwiftUI

struct PaywallView: View {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var isEligibleForTrial = false

    private let features: [(icon: String, title: String)] = [
        ("play.rectangle.fill", "Video Playback Mode"),
        ("phone.fill", "Fake Call Mode"),
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

                        Text("Unlock premium recording modes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

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

                    // Price & Trial Info
                    if subscriptionManager.isLoadingProducts {
                        ProgressView("Loading subscription...")
                            .padding()
                    } else if let product = subscriptionManager.products.first {
                        VStack(spacing: 8) {
                            // Price is always prominently displayed first
                            Text("\(product.displayPrice) / month")
                                .font(.title2.bold())

                            if isEligibleForTrial {
                                Text("Includes 2-week free trial")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Text("You won't be charged until the trial ends. After the 2-week free trial, you will be automatically charged \(product.displayPrice) per month until you cancel.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }

                            Text("Auto-renewable subscription. Cancel anytime in Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text("Unable to load subscription")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Tap to Retry") {
                                Task { await subscriptionManager.loadProducts() }
                            }
                            .font(.subheadline.bold())
                        }
                        .padding()
                    }

                    // Subscribe button
                    Button {
                        isPurchasing = true
                        Task {
                            await subscriptionManager.purchase()
                            isPurchasing = false
                            if subscriptionManager.isPremium {
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
                                Text("Subscribe Now")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(subscriptionManager.products.isEmpty ? Color.gray : Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                    }
                    .disabled(isPurchasing || subscriptionManager.products.isEmpty)
                    .padding(.horizontal)

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
                        Text("TravelVid Premium Monthly Subscription")
                            .font(.caption)
                            .foregroundStyle(.secondary)

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
            .task {
                if subscriptionManager.products.isEmpty {
                    await subscriptionManager.loadProducts()
                }
                isEligibleForTrial = await subscriptionManager.isEligibleForIntroOffer()
            }
        }
    }
}
