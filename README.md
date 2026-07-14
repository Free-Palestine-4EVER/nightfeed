# NIGHTFEED

A native Swift + SpriteKit survivor-roguelite for iOS. Top-down arena, floating joystick, auto-firing
weapons, escalating waves, level-up choices, meta-progression shop, AdMob monetization. iOS 16+,
portrait-only, built and verified against Xcode 26.6 / iOS 26.5 Simulator.

Every visual (art, particles, UI) and every sound is generated in code at build/runtime — there are no
bundled image or audio assets, so there is nothing that can go "missing."

## Project layout

```
NightFeed.xcodeproj/         Xcode project (synchronized-root-group — drop any .swift file into
                              NightFeed/ and it auto-joins the build target, no project editing needed)
NightFeed-Info.plist          Info.plist source (merged with build-setting-driven keys)
NightFeed/
  App/                        SwiftUI entry point (NightFeedApp, GameRootView -> SpriteView)
  Scenes/                     MenuScene, GameScene, GameOverScene
  Systems/                    GameConstants, GameTypes, Balance (all tuning data), PoolManager,
                               JuiceEffects, AudioManager (procedural SFX/music), MetaProgressionStore,
                               WeaponSystem, EnemySpawner, XPSystem, UpgradeManager, AdsManager, SpatialGrid
  Entities/                   Enemy, Projectile, XPGem (pooled), PlayerController
  UI/                         VirtualJoystick, LevelUpOverlay
  Assets.xcassets/            App icon (procedural, 1024pt, no alpha), accent color, launch background color
```

## What's implemented

- **6 weapons**, each with distinct behavior: Fang Bolt (straight shot), Ember Orbit (orbiters), Nova
  Pulse (AoE burst), Blood Lance (piercing), Bat Swarm (homing), Reaper Whirl (melee whirl).
- **2 evolutions**: Fang Bolt + maxed Crit Focus -> Moonfang Barrage; Reaper Whirl + maxed Vitality ->
  Crimson Maelstrom (lifesteal).
- **8 passives**: move speed, damage, fire rate, max health, XP magnet radius, armor, multishot, crit.
- **4 enemy types**: Swarmling, Bloodbat, Hollow Brute, and the Nightmaw mini-boss (timed spawns).
- **Object pooling** for every enemy/projectile/gem/damage-label/particle-emitter — nothing is
  allocated or deallocated during gameplay (see `PoolManager.swift`).
- **No SpriteKit physics** — collision is manual distance/grid checks (`SpatialGrid.swift`) run by
  whichever system needs it, specifically to avoid O(n^2) checks across hundreds of enemies.
- **Meta-progression**: gold earned per run buys 5 permanent starting upgrades, persisted via
  `UserDefaults` (`MetaProgressionStore.swift`).
- **AdMob**: rewarded "revive once" (shown automatically on death) and "double gold" (on the game-over
  screen), interstitial every 3rd completed run, ATT prompt on first launch.

## 1. Open in Xcode and set signing

Open `NightFeed.xcodeproj`. The target is already set to **Automatic** code signing with a development
team baked in (`6JW6JNN28V`) — Xcode → target **NightFeed** → **Signing & Capabilities** → change
**Team** to your own Apple Developer team. Bundle identifier is `com.loom.nightfeed` — change it in the
same tab (or in `project.pbxproj`, `PRODUCT_BUNDLE_IDENTIFIER`, two places: Debug and Release configs)
to your own reverse-DNS identifier before you archive.

The AdMob Swift Package (`swift-package-manager-google-mobile-ads`, resolved to 11.13.0) resolves
automatically the first time you open the project with network access — Xcode → File → Packages →
Resolve Package Versions if it doesn't kick off on its own.

## 2. Swap in your real AdMob IDs (currently Google's public TEST IDs)

Every ID below is Google's official sample/test ID and is clearly marked in the source. Replace all
four with the real values from your own AdMob account:

1. **`NightFeed-Info.plist`, line 27** — `GADApplicationIdentifier`: your AdMob **App ID**.
2. **`NightFeed/Systems/AdsManager.swift`, line 18** — `rewardedAdUnitID`: your **Rewarded** ad unit ID.
3. **`NightFeed/Systems/AdsManager.swift`, line 20** — `interstitialAdUnitID`: your **Interstitial**
   ad unit ID.
4. **`NightFeed-Info.plist`, `SKAdNetworkItems`** — currently contains only Google's own network ID
   (`cstr6suwn9.skadnetwork`). Before submitting, copy the **full current list** of SKAdNetwork IDs from
   Google's AdMob documentation (it changes over time as new ad-network partners are added) and paste
   the complete list in — an incomplete list under-reports install attribution but will not break ads.

Create your ad units at [apps.admob.com](https://apps.admob.com) → your app → Ad units → one **Rewarded**
and one **Interstitial** unit. Create the AdMob "app" entry itself first if you haven't (App ID comes
from there).

## 3. Create the app record in App Store Connect

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **My Apps** → **+** → **New App**.
- Platform: iOS
- Name: NIGHTFEED (or your localized title — must be unique on the Store)
- Primary language: English (or your choice)
- Bundle ID: the one you set in Step 1 (must already exist under your account's Identifiers —
  Certificates, Identifiers & Profiles → Identifiers → **+** if it's not there yet)
- SKU: any unique internal string, e.g. `nightfeed-ios-01`
- **Category: Games** → subcategory Action or Arcade (your call)

## 4. App Privacy, age rating, AdMob's required answers

**App Privacy** (App Store Connect → your app → App Privacy):
- Data collected: **Device ID / Identifiers** — used for **Advertising** and **Analytics**, linked to
  the user, used for tracking (this is what AdMob/ATT actually collects; answer honestly here rather
  than copying a template — it directly affects your privacy "nutrition label").
- The app ships a `PrivacyInfo.xcprivacy` (`NightFeed/PrivacyInfo.xcprivacy`) declaring
  `NSPrivacyTracking = true` and the `UserDefaults` required-reason API usage (reason `CA92.1`, used only
  for the app's own meta-progression, no third-party data). Xcode merges this with the ad SDK's own
  bundled privacy manifest automatically at archive time — you don't need to edit it unless you add a
  new required-reason API yourself.

**Age rating** (App Store Connect → App Information → Age Rating): answer the standard questionnaire.
NightFeed has cartoon/fantasy violence (enemies "defeated," no gore/blood text) and third-party ads —
expect roughly a 9+ or 12+ rating depending on your exact answers; there's no user-generated content,
gambling, or real-money mechanics to flag.

**AdMob-required App Store Connect settings**: enable **"Allow tracking"** in App Store Connect's ATT
settings if prompted, and make sure the age rating questionnaire's "Unrestricted Web Access" and
"Advertising" answers match "Yes" (the game shows third-party ads).

## 5. Screenshots + preview

Required sizes (App Store Connect will list exactly what's mandatory for your minimum deployment
target — as of iOS 16+ this is typically just the 6.9" and 6.5" display sizes, plus 13" iPad if you ever
enable iPad; NightFeed is iPhone-only so iPad isn't required):
- **6.9" (iPhone 17 Pro Max class), 1320 × 2868px** — capture via Simulator: boot an iPhone 17 Pro Max
  simulator, `xcrun simctl io booted screenshot shot.png` while the app is running, or Cmd+S in the
  Simulator window.
- **6.5" (iPhone 11 Pro Max / XS Max class), 1242 × 2688px** — same process on that simulator, only
  needed if you don't provide 6.9" and want the widest compatibility.

Capture at least 3 shots: the menu, mid-combat (with enemies + a weapon effect visible), and the
level-up card screen — these are the moments that sell a survivor-roguelite. App preview video (up to
30s) is optional but recommended; screen-record the Simulator (Simulator → File → Record Screen) over Cmd+R'd gameplay footage from Step 1's build.

## 6. Archive, validate, upload

1. Xcode → select **Any iOS Device (arm64)** as the run destination (not a simulator).
2. **Product → Archive.**
3. When the Organizer opens, select the archive → **Validate App** → follow the prompts (uses your
   Step 1 signing team automatically) → fix anything it flags.
4. **Distribute App → App Store Connect → Upload.**
5. In App Store Connect, the build appears under **TestFlight**/your app version within a few minutes
   to ~an hour — attach it to your version under **App Store → Build**.

## 7. Submit for review

Add release notes if this is an update, then **Submit for Review**. Common rejection reasons for
ad-monetized games, and how this project already avoids them:

- **"Ads shown before app is usable" / interstitial spam** — NightFeed never shows an ad on cold
  launch; the earliest possible ad is the death-screen revive offer, which is user-initiated (a button
  tap), and the interstitial only fires after a full completed run, capped at 1 in 3 runs.
- **Rewarded ad doesn't actually grant the reward** — `AdsManager.showRewarded` only calls
  `onComplete(true)` from the SDK's own `didEarnReward` callback, never optimistically; test this for
  real once you swap in production IDs (test IDs always fill, production fill is not guaranteed — the
  revive/double-gold buttons gracefully no-op to "ad not available" if `showRewarded` reports `false`,
  they don't hang or crash).
- **ATT prompt missing or mistimed** — requested once on first Menu appearance, before any ad is shown,
  matching Apple's guidance to ask before the behavior it gates (ad targeting) begins.
- **Privacy manifest / required-reason API declarations missing** — `PrivacyInfo.xcprivacy` is present
  (Step 4); if Xcode's build-time privacy report (Product → Archive → the report Xcode generates) flags
  a *new* required-reason API once you add code of your own, add its reason code there.
- **Broken/incomplete IAP or ad flow reviewers can't get through** — there is no IAP. Every ad surface
  (revive, double gold, interstitial) degrades gracefully with no ad configured, so a reviewer testing
  before your AdMob account has real fill will never see a stuck or blank screen.
- **Crashes on rotation / unsupported orientation** — the app is hard-locked to portrait
  (`UISupportedInterfaceOrientations` + `TARGETED_DEVICE_FAMILY = 1`, iPhone only); nothing to test here,
  but don't remove that lock without adding real landscape layout.

## What you need to supply

- **Apple Developer Program membership** ($99/yr) — for the signing team in Step 1 and App Store Connect
  access in Steps 3–7.
- **An AdMob account** (free) — for the four real IDs in Step 2. Google review of a new AdMob account/app
  can take a day or two before ads serve at meaningful fill; test IDs work immediately and indefinitely
  for development.
- **Your own app icon concept**, if you want to replace the procedurally-generated one — it lives at
  `NightFeed/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (1024×1024, no alpha channel — Apple
  rejects icons with an alpha channel at validate time, so if you regenerate it, flatten to opaque).
- **Screenshots** (Step 5) — the build itself can produce all of these; no external design tool needed.

## Notes on what's deliberately NOT here

- No storyboards/XIBs — the whole UI (menus, HUD, cards, pause screen) is SpriteKit nodes built in code,
  matching the "no missing assets" requirement.
- No SwiftData/CoreData — the only persistence is `UserDefaults` via `MetaProgressionStore`, which is
  all a gold-and-upgrade-tiers meta-progression system needs.
- No banner ads — the brief specified rewarded + interstitial only; adding a banner is a small addition
  to `AdsManager.swift` if you want one later (Google's `BannerView`/`GADBannerView` following the same
  GAD-prefixed pattern already used here).
