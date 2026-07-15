import SwiftUI
import GoogleMobileAds
import UIKit

class AdMobManager: NSObject, ObservableObject {
    static let shared = AdMobManager()

    // Properties updated to native Swift naming
    private var interstitial: InterstitialAd?
    private var rewardedAd: RewardedAd?

    // Track pending completion handler for rewarded ads
    private var rewardedAdCompletion: ((Bool) -> Void)?
    private var didEarnReward = false
    private var interstitialCompletion: (() -> Void)?
    private var isSDKInitialized = false
    private var isSDKInitializing = false
    private var isInterstitialLoading = false
    private var isRewardedLoading = false
    private var initializationCompletions: [() -> Void] = []

    // MARK: - Ad Unit IDs
    private(set) var interstitialID: String = ""
    private(set) var rewardedID: String = ""

    override init() {
        super.init()
        loadConfig()
    }
    
    private func loadConfig() {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let adMobConfig = plist["AdMob"] as? [String: String] else {
            print("🚨 Failed to load AdMob config from Config.plist")
            return
        }
        
        interstitialID = adMobConfig["InterstitialID"] ?? ""
        rewardedID = adMobConfig["RewardedID"] ?? ""
        print("✅ AdMob config loaded successfully")
    }
    
    // MARK: - Initialization
    func initializeAdMob() {
        ensureSDKInitialized()
    }
    
    // MARK: - Interstitial Logic
    func loadInterstitial() {
        guard isSDKInitialized else {
            ensureSDKInitialized()
            return
        }

        guard !interstitialID.isEmpty else {
            print("❌ AdMob interstitial request skipped: InterstitialID is missing from Config.plist.")
            return
        }

        guard !isInterstitialLoading else { return }
        isInterstitialLoading = true

        let request = Request()
        InterstitialAd.load(with: interstitialID, request: request) { [weak self] ad, error in
            guard let self else { return }
            self.isInterstitialLoading = false

            if let error = error {
                self.interstitial = nil
                self.logLoadError(error, format: "interstitial")
                return
            }

            guard let ad else {
                print("❌ AdMob interstitial load returned no ad and no error.")
                return
            }

            self.interstitial = ad
            ad.fullScreenContentDelegate = self
            self.logLoadedAd(format: "Interstitial", responseInfo: ad.responseInfo)
        }
    }
    
    func showInterstitialAd(completion: @escaping () -> Void, attempt: Int = 0) {
        guard let root = rootVC else {
            print("⚠️ AdMob interstitial not presented: no active root view controller.")
            ensureSDKInitialized()
            completion()
            return
        }

        if root.presentedViewController != nil {
            if attempt < 3 {
                ensureSDKInitialized()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.showInterstitialAd(completion: completion, attempt: attempt + 1)
                }
                return
            }
            print("⚠️ AdMob interstitial not presented: another screen is already being presented.")
            completion()
            return
        }

        if interstitialID.isEmpty {
            print("Interstitial ID is empty. Check Config.plist.")
            completion()
            return
        }

        if let ad = interstitial {
            interstitial = nil
            interstitialCompletion = completion
            print("▶️ Presenting AdMob interstitial.")
            ad.present(from: root)
            return
        }

        // Start loading for next attempt while keeping UX non-blocking.
        print("⚠️ AdMob interstitial not ready; loading one for the next opportunity.")
        if !isSDKInitialized {
            ensureSDKInitialized { [weak self] in
                self?.showInterstitialAd(completion: completion, attempt: attempt + 1)
            }
            return
        }
        loadInterstitial()
        completion()
    }

    func prewarmInterstitialIfNeeded() {
        if interstitial == nil, isSDKInitialized {
            loadInterstitial()
        }
    }
    
    // MARK: - Rewarded Logic
    func loadRewardedAd() {
        guard isSDKInitialized else {
            ensureSDKInitialized()
            return
        }

        guard !rewardedID.isEmpty else {
            print("❌ AdMob rewarded request skipped: RewardedID is missing from Config.plist.")
            return
        }

        guard !isRewardedLoading else { return }
        isRewardedLoading = true

        let request = Request()
        RewardedAd.load(with: rewardedID, request: request) { [weak self] ad, error in
            guard let self else { return }
            self.isRewardedLoading = false

            if let error = error {
                self.rewardedAd = nil
                self.logLoadError(error, format: "rewarded")
                return
            }

            guard let ad else {
                print("❌ AdMob rewarded load returned no ad and no error.")
                return
            }

            self.rewardedAd = ad
            ad.fullScreenContentDelegate = self
            self.logLoadedAd(format: "Rewarded", responseInfo: ad.responseInfo)
        }
    }
    
    func showRewardedAd(completion: @escaping (Bool) -> Void) {
        ensureSDKInitialized { [weak self] in
            guard let self else {
                completion(false)
                return
            }

            guard let root = self.rootVC else {
                completion(false)
                return
            }

            if let ad = self.rewardedAd {
                self.rewardedAd = nil
                self.rewardedAdCompletion = completion
                self.didEarnReward = false

                print("▶️ Presenting AdMob rewarded ad.")
                ad.present(from: root) { [weak self] in
                    print("✅ AdMob reward earned.")
                    self?.didEarnReward = true
                }
            } else {
                print("Rewarded ad wasn't ready.")
                self.loadRewardedAd()
                completion(false)
            }
        }
    }

    private func ensureSDKInitialized(completion: (() -> Void)? = nil) {
        if let completion {
            initializationCompletions.append(completion)
        }

        guard !isSDKInitialized else {
            flushInitializationCompletions()
            return
        }

        guard !isSDKInitializing else { return }
        isSDKInitializing = true

        MobileAds.shared.start { [weak self] _ in
            guard let self else { return }
            self.isSDKInitializing = false
            self.isSDKInitialized = true
            print("✅ AdMob SDK initialized; preloading interstitial and rewarded ads.")
            self.loadInterstitial()
            self.loadRewardedAd()
            self.flushInitializationCompletions()
        }
    }

    private func flushInitializationCompletions() {
        let completions = initializationCompletions
        initializationCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func logLoadedAd(format: String, responseInfo: ResponseInfo) {
        let responseID = responseInfo.responseIdentifier ?? "unavailable"
        let source = responseInfo.loadedAdNetworkResponseInfo?.adSourceName ??
            responseInfo.loadedAdNetworkResponseInfo?.adNetworkClassName ?? "unknown"
        print("✅ AdMob \(format) loaded. responseID=\(responseID), source=\(source)")
    }

    private func logLoadError(_ error: Error, format: String) {
        let nsError = error as NSError
        let category: String

        switch nsError.code {
        case 0: category = "Invalid request"
        case 1: category = "No fill"
        case 2: category = "Network error"
        case 3: category = "Server error"
        case 4: category = "OS version too low"
        case 5: category = "Timeout"
        case 7: category = "Invalid mediation response"
        case 8: category = "Mediation adapter error"
        case 10: category = "Invalid mediation ad size"
        case 11: category = "Internal error"
        case 12: category = "Invalid argument"
        case 19: category = "Ad already used"
        case 20: category = "Missing app ID"
        case 21: category = "Invalid ad response"
        default: category = "Unknown error"
        }

        print("❌ AdMob \(format) load failed [\(category)] domain=\(nsError.domain) code=\(nsError.code): \(nsError.localizedDescription)")

        if let reason = nsError.localizedFailureReason {
            print("   Reason: \(reason)")
        }

        if let responseInfo = nsError.userInfo.values.compactMap({ $0 as? ResponseInfo }).first {
            let responseID = responseInfo.responseIdentifier ?? "unavailable"
            print("   Response ID: \(responseID)")

            for network in responseInfo.adNetworkInfoArray {
                let source = network.adSourceName ?? network.adNetworkClassName
                let result = network.error.map {
                    let networkError = $0 as NSError
                    return "error \(networkError.code): \(networkError.localizedDescription)"
                } ?? "no ad returned"
                print("   Network \(source) (\(Int(network.latency * 1_000)) ms): \(result)")
            }
        }
    }
    
    // MARK: - Helper to find the Root View Controller
    var rootVC: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        return window.rootViewController
    }
}

// MARK: - Delegate to Reload Ads
extension AdMobManager: FullScreenContentDelegate {

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("✅ AdMob full-screen ad presented.")
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        print("✅ AdMob impression recorded.")
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        print("ℹ️ AdMob click recorded.")
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("ℹ️ AdMob full-screen ad dismissed; preloading the next ad.")
        if ad is InterstitialAd {
            interstitialCompletion?()
            interstitialCompletion = nil
            loadInterstitial()
        } else if ad is RewardedAd {
            // Call stored completion with reward status, then reload
            rewardedAdCompletion?(didEarnReward)
            rewardedAdCompletion = nil
            didEarnReward = false
            loadRewardedAd()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        let nsError = error as NSError
        print("❌ AdMob failed to present domain=\(nsError.domain) code=\(nsError.code): \(nsError.localizedDescription)")
        if ad is InterstitialAd {
            interstitialCompletion?()
            interstitialCompletion = nil
            loadInterstitial()
        } else if ad is RewardedAd {
            // Call stored completion with false since ad failed to show
            rewardedAdCompletion?(false)
            rewardedAdCompletion = nil
            didEarnReward = false
            loadRewardedAd()
        }
    }
}
