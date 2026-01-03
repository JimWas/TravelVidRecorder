import SwiftUI
import GoogleMobileAds
import UIKit

class AdMobManager: NSObject, ObservableObject {
    static let shared = AdMobManager()
    
    // Properties to hold the loaded ads
    private var interstitial: InterstitialAd?
    private var rewardedAd: RewardedAd?
    
    // MARK: - Ad Unit IDs
    
    // 1. Interstitial ID (Pop-up after recording)
    // NOTE: This is still the Google Test ID. Replace with your own "Interstitial" ID from AdMob dashboard.
    let interstitialID = "ca-app-pub-3057383894764696/5247040863"
    
    // 2. Rewarded ID (Watch to Save) - YOUR REAL ID
    let rewardedID     = "ca-app-pub-3057383894764696/5247040863"
    
    override init() {
        super.init()
    }
    
    // MARK: - Initialization
    func initializeAdMob() {
        // Initialize the Google Mobile Ads SDK
        MobileAds.shared.start { [weak self] status in
            print("AdMob SDK Initialized")
            // Load ads only after SDK is ready
            self?.loadInterstitial()
            self?.loadRewardedAd()
        }
    }
    
    // MARK: - Interstitial (Pop-up) Logic
    func loadInterstitial() {
        let request = Request()
        InterstitialAd.load(with: interstitialID, request: request) { [weak self] ad, error in
            if let error = error {
                print("Failed to load interstitial: \(error.localizedDescription)")
                return
            }
            self?.interstitial = ad
            self?.interstitial?.fullScreenContentDelegate = self
        }
    }
    
    func showInterstitialAd() {
        guard let root = rootVC else { return }
        
        if let ad = interstitial {
            ad.present(from: root)
        } else {
            print("Interstitial ad wasn't ready.")
            loadInterstitial() // Try reloading for next time
        }
    }
    
    // MARK: - Rewarded (Watch to Save) Logic
    func loadRewardedAd() {
        let request = Request()
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
            ad.present(from: root) {
                // This closure is called when the user earns the reward
                print("User earned reward.")
                completion(true)
            }
        } else {
            print("Rewarded ad wasn't ready.")
            loadRewardedAd()
            // Optional: If ad fails to load, do you want to let them save anyway?
            // If yes, change to completion(true). If no, keep completion(false).
            completion(false)
        }
    }
    
    // MARK: - Helper to find the Root View Controller
    var rootVC: UIViewController? {
        // Finds the active window to display the ad over
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        return window.rootViewController
    }
}

// MARK: - Delegate to Reload Ads
extension AdMobManager: FullScreenContentDelegate {
    
    /// Tells the delegate that the ad dismissed full screen content.
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("Ad dismissed. Reloading...")
        
        // Immediately load a fresh ad so it's ready for next time
        if ad is InterstitialAd {
            loadInterstitial()
        } else if ad is RewardedAd {
            loadRewardedAd()
        }
    }
    
    /// Tells the delegate that the ad failed to present full screen content.
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("Ad failed to present: \(error.localizedDescription)")
        
        // Retry loading on failure
        if ad is InterstitialAd {
            loadInterstitial()
        } else if ad is RewardedAd {
            loadRewardedAd()
        }
    }
}
