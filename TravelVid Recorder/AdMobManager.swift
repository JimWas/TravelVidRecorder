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

    // MARK: - Ad Unit IDs
    let interstitialID = "ca-app-pub-3057383894764696/4200169611"
    let rewardedID     = "ca-app-pub-3057383894764696/5439021675"

    override init() {
        super.init()
    }
    
    // MARK: - Initialization
    func initializeAdMob() {
        // Modern SDK uses MobileAds.shared.start
        MobileAds.shared.start { status in
            print("AdMob SDK Initialized")
            self.loadInterstitial()
            self.loadRewardedAd()
        }
    }
    
    // MARK: - Interstitial Logic
    func loadInterstitial() {
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
        guard let root = rootVC else {
            completion()
            return
        }
        if root.presentedViewController != nil {
            completion()
            return
        }
        
        if let ad = interstitial {
            interstitialCompletion = completion
            // New signature: from:
            ad.present(from: root)
        } else {
            print("Interstitial ad wasn't ready.")
            loadInterstitial()
            completion()
        }
    }
    
    // MARK: - Rewarded Logic
    func loadRewardedAd() {
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
        guard let root = rootVC else {
            completion(false)
            return
        }

        if let ad = rewardedAd {
            // Store completion to call it when ad dismisses or fails
            rewardedAdCompletion = completion
            didEarnReward = false

            // New signature: from:userDidEarnRewardHandler:
            ad.present(from: root) { [weak self] in
                print("User earned reward.")
                self?.didEarnReward = true
            }
        } else {
            print("Rewarded ad wasn't ready.")
            loadRewardedAd()
            completion(false)
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
        if ad is InterstitialAd {
            interstitialCompletion?()
            interstitialCompletion = nil
            loadInterstitial()
        } else if ad is RewardedAd {
            rewardedAdCompletion?(false)
            rewardedAdCompletion = nil
            didEarnReward = false
            loadRewardedAd()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("Ad failed to present: \(error.localizedDescription)")
        if ad is InterstitialAd {
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
