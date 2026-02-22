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

        let request = Request()
        // New signature: with:request:completionHandler:
        InterstitialAd.load(with: interstitialID, request: request) { [weak self] ad, error in
            if let error = error {
                print("Failed to load interstitial: \(error.localizedDescription)")
                return
            }
            self?.interstitial = ad
            self?.interstitial?.fullScreenContentDelegate = self
        }
    }
    
    func showInterstitialAd(completion: @escaping () -> Void) {
        guard let root = rootVC, root.presentedViewController == nil else {
            completion()
            return
        }

        if let ad = interstitial {
            interstitialCompletion = completion
            ad.present(from: root)
            return
        }

        // Never trigger SDK startup during stop-flow UI transitions.
        print("Interstitial ad wasn't ready.")
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

        let request = Request()
        // New signature: with:request:completionHandler:
        RewardedAd.load(with: rewardedID, request: request) { [weak self] ad, error in
            if let error = error {
                print("Failed to load rewarded ad: \(error.localizedDescription)")
                return
            }
            self?.rewardedAd = ad
            self?.rewardedAd?.fullScreenContentDelegate = self
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
                self.rewardedAdCompletion = completion
                self.didEarnReward = false

                ad.present(from: root) { [weak self] in
                    print("User earned reward.")
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
            print("AdMob SDK Initialized")
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

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
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
        print("Ad failed to present: \(error.localizedDescription)")
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
