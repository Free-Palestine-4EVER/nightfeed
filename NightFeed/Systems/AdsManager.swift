import UIKit
import GoogleMobileAds
import AppTrackingTransparency
import AdSupport

/// Owns the Google Mobile Ads SDK lifecycle (rewarded + interstitial ads) and App Tracking Transparency.
/// MenuScene/GameOverScene/GameScene call through this single shared instance — no other system should
/// touch GoogleMobileAds or ATTrackingManager directly.
///
/// Uses the classic `GAD`-prefixed GoogleMobileAds API surface (`GADMobileAds`, `GADRewardedAd`,
/// `GADInterstitialAd`, `GADFullScreenContentDelegate`, `GADRequest`). The SDK resolved for this project
/// (11.13.0, per Package.resolved) ships as a pure Objective-C binary xcframework with no Swift-native
/// non-prefixed overlay, so the `GAD`-prefixed names are what actually compiles against it.
final class AdsManager: NSObject {
    static let shared = AdsManager()

    // TEST ID -- swap before submission, see README
    private let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    // TEST ID -- swap before submission, see README
    private let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"

    private var didConfigure = false

    private var rewardedAd: GADRewardedAd?
    private var isLoadingRewardedAd = false
    private var isPresentingRewardedAd = false
    private var pendingRewardedCompletion: ((Bool) -> Void)?
    private var rewardedAdDidEarnReward = false

    private var interstitialAd: GADInterstitialAd?
    private var isLoadingInterstitialAd = false
    private var isPresentingInterstitialAd = false

    private override init() {
        super.init()
    }

    // MARK: - Configure

    /// Starts the Google Mobile Ads SDK and kicks off loading the first rewarded + interstitial ad.
    /// Safe to call more than once (no-op after the first successful call). Call this before requesting
    /// ATT, not after — the Mobile Ads SDK wants to be started ahead of the tracking-authorization prompt.
    func configure() {
        guard !didConfigure else { return }
        didConfigure = true
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        loadRewardedAd()
        loadInterstitialAd()
    }

    // MARK: - App Tracking Transparency

    /// If ATT has not yet been requested this install, requests it via
    /// ATTrackingManager.requestTrackingAuthorization(completionHandler:) on iOS 14+. Always calls
    /// `completion` exactly once when done (immediately if already requested, or after the OS prompt
    /// resolves either way).
    func requestTrackingIfNeeded(completion: (() -> Void)?) {
        guard !MetaProgressionStore.shared.hasRequestedATT else {
            completion?()
            return
        }
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { _ in
                MetaProgressionStore.shared.hasRequestedATT = true
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } else {
            MetaProgressionStore.shared.hasRequestedATT = true
            completion?()
        }
    }

    // MARK: - Rewarded

    /// Shows a rewarded ad from the current top view controller if one is loaded/ready. If none is ready,
    /// calls onComplete(false) immediately (never hangs the caller). On successful reward earn, calls
    /// onComplete(true); on dismiss without earning a reward (or on any failure), calls onComplete(false).
    /// Always starts loading the next rewarded ad after this one is shown/fails.
    func showRewarded(onComplete: @escaping (_ earned: Bool) -> Void) {
        guard !isPresentingRewardedAd else {
            // Already mid-presentation from an earlier call — don't clobber its pending completion or
            // kick off a reload that could steal the reference to the ad currently on screen.
            onComplete(false)
            return
        }
        guard let ad = rewardedAd, let topVC = topViewController() else {
            onComplete(false)
            loadRewardedAd()
            return
        }

        isPresentingRewardedAd = true
        pendingRewardedCompletion = onComplete
        rewardedAdDidEarnReward = false
        ad.fullScreenContentDelegate = self
        ad.present(fromRootViewController: topVC) { [weak self] in
            self?.rewardedAdDidEarnReward = true
        }
    }

    private func loadRewardedAd() {
        guard !isLoadingRewardedAd else { return }
        isLoadingRewardedAd = true
        GADRewardedAd.load(withAdUnitID: rewardedAdUnitID, request: GADRequest()) { [weak self] ad, error in
            guard let self else { return }
            self.isLoadingRewardedAd = false
            if error != nil {
                // Failed to load (no fill, network, misconfiguration, ...) — leave rewardedAd nil so the
                // next showRewarded() call reports unready rather than crashing.
                self.rewardedAd = nil
                return
            }
            ad?.fullScreenContentDelegate = self
            self.rewardedAd = ad
        }
    }

    private func finishRewardedPresentation() {
        let completion = pendingRewardedCompletion
        let earned = rewardedAdDidEarnReward
        pendingRewardedCompletion = nil
        rewardedAdDidEarnReward = false
        isPresentingRewardedAd = false
        rewardedAd = nil
        loadRewardedAd()
        completion?(earned)
    }

    // MARK: - Interstitial

    /// Checks MetaProgressionStore.shared.shouldShowInterstitial(); if true and an interstitial is ready,
    /// shows it from the current top view controller, then starts loading the next one. No-op (including
    /// no crash/hang) if not due or not ready.
    func showInterstitialIfDue() {
        guard !isPresentingInterstitialAd else { return }
        guard MetaProgressionStore.shared.shouldShowInterstitial() else { return }
        guard let ad = interstitialAd, let topVC = topViewController() else { return }
        isPresentingInterstitialAd = true
        ad.fullScreenContentDelegate = self
        ad.present(fromRootViewController: topVC)
    }

    private func loadInterstitialAd() {
        guard !isLoadingInterstitialAd else { return }
        isLoadingInterstitialAd = true
        GADInterstitialAd.load(withAdUnitID: interstitialAdUnitID, request: GADRequest()) { [weak self] ad, error in
            guard let self else { return }
            self.isLoadingInterstitialAd = false
            if error != nil {
                self.interstitialAd = nil
                return
            }
            ad?.fullScreenContentDelegate = self
            self.interstitialAd = ad
        }
    }

    private func finishInterstitialPresentation() {
        isPresentingInterstitialAd = false
        interstitialAd = nil
        loadInterstitialAd()
    }

    // MARK: - Top view controller resolution

    /// SwiftUI's WindowGroup gives us no directly-injected UIViewController, so we walk the active
    /// UIWindowScene's key window down to the deepest presented view controller ourselves.
    private func topViewController() -> UIViewController? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first
        guard let scene = activeScene else { return nil }

        let window = scene.windows.first { $0.isKeyWindow } ?? scene.windows.first
        guard var top = window?.rootViewController else { return nil }

        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - GADFullScreenContentDelegate

extension AdsManager: GADFullScreenContentDelegate {
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        if let rewarded = ad as? GADRewardedAd, rewarded === rewardedAd {
            finishRewardedPresentation()
        } else if ad is GADInterstitialAd {
            finishInterstitialPresentation()
        }
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        if let rewarded = ad as? GADRewardedAd, rewarded === rewardedAd {
            finishRewardedPresentation()
        } else if ad is GADInterstitialAd {
            finishInterstitialPresentation()
        }
    }
}
