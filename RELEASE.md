# NIGHTFEED — App Store submission pack

- **Bundle ID:** `com.loom.nightfeed` (App ID `5RKRH3ZUYP`, registered)
- **Team:** Zeid Naser — `6JW6JNN28V`
- **SKU:** `NIGHTFEED001`
- **Version:** 1.0 (build 1)
- **Signed IPA:** `build-release/export/NightFeed.ipa` — already exported, signed with the real
  Apple Distribution certificate and a matching App Store provisioning profile (`NightFeed App Store v2`,
  both registered via the App Store Connect API). Ready to upload the moment the app record exists.
- **Primary locale:** English (US).

---

## Name & subtitle

**Name:** NIGHTFEED
**Subtitle (30 char max):** Survivor roguelite

## Promotional text (170 max)

> Auto-firing weapons, escalating waves, and a level-up choice every time you survive. Six weapons,
> two evolutions, a mini-boss, and a permanent upgrade shop between runs.

## Description

> **Survive the night.**
>
> NIGHTFEED is a top-down survivor-roguelite: drag to move, and your weapons fire on their own at
> whatever's closest. Waves of nocturnal swarmers escalate the longer you last — collect the XP gems
> they drop to level up and pick a new weapon, passive, or evolution every time.
>
> **Six weapons, two evolutions**
> Fang Bolt, Ember Orbit, Nova Pulse, Blood Lance, Bat Swarm, Reaper Whirl, Void Rift, and Star Shard —
> each with a completely different attack pattern. Max the right weapon and passive together to unlock
> an evolved form.
>
> **A real difficulty curve**
> Four enemy types, including the Nightmaw mini-boss on a timer, ramping smoothly across an
> 18-minute run instead of spiking all at once.
>
> **Permanent progression**
> Gold earned every run buys permanent upgrades in the shop — more health, more damage, a starting
> level boost, even a familiar that fights alongside you.
>
> Free to play, with optional ads: watch one to revive once per run or double your gold, never
> required to keep playing.

## Keywords (100 char max, comma-separated, no spaces)

```
survivor,roguelite,arcade,action,waves,shooter,idle,auto,battler,horde,survival,night,arena
```

## Category

- Primary: **Games**
- Subcategory: **Action** (secondary: Arcade)

## Age rating

Expected **9+ or 12+** — cartoon/fantasy violence (enemies "defeated," no blood/gore), infrequent
third-party ads, no user-generated content, no gambling, no real-money purchases. Answer the
questionnaire honestly in App Store Connect; do not assume 4+.

## URLs (REQUIRED — Apple will not accept the submission without these)

- **Privacy policy URL:** https://free-palestine-4ever.github.io/nightfeed-legal/privacy — **live**.
- **Support URL:** https://free-palestine-4ever.github.io/nightfeed-legal/support — **live**.
- Marketing URL: optional, not set.
- Source: https://github.com/Free-Palestine-4EVER/nightfeed-legal (public, GitHub Pages).

The (now-abandoned) Vercel deploy at `nightfeed-game` landed behind account-wide Deployment
Protection and was replaced by the GitHub Pages site above — no action needed there.

---

## Privacy "nutrition label" (App Store Connect → App Privacy)

| Question | Answer |
|---|---|
| Do you collect data from this app? | **Yes** — Device ID / Identifiers, via the AdMob SDK. |
| Used for | Third-party advertising, analytics (AdMob's own). |
| Linked to identity? | No. |
| Used for tracking? | Yes (gated by the ATT prompt already in the app — decline and the game still fully works). |

`PrivacyInfo.xcprivacy` in the app declares `NSPrivacyTracking = true` and the `UserDefaults`
required-reason API (`CA92.1`, app's own local save data only). Xcode merges this with Google Mobile
Ads' own bundled privacy manifest automatically at archive time.

## App Review notes (paste into "Notes for Review")

> No account or sign-in of any kind — the game is playable immediately on launch. All ad units are
> Google's official TEST IDs in this build (clearly marked in source, `AdsManager.swift`) — replace
> with real AdMob IDs before this build actually goes live publicly, per the SHIP README. Rewarded ads
> (revive / double gold) and the interstitial (every 3rd completed run) are all optional; declining
> never blocks progress. No in-app purchases.

---

## Still to do (Apple's API cannot do this one — see apple-signing-gotchas memory)

1. **Create the app record** — App Store Connect → Apps → "+" → New App. Platform iOS, name
   "NIGHTFEED", primary language English (US), bundle ID `com.loom.nightfeed`, SKU `NIGHTFEED001`.
   This is the only step Apple's API refuses outright (confirmed: `apps` only allows
   GET_COLLECTION/GET_INSTANCE/UPDATE, not CREATE) — everything else below, I do via the API once
   this exists.
2. Confirm **EU trader status** is set on the account (Business settings) — this blocked a past
   submission on this same account before it was resolved; may already be fine now, worth a glance.
3. Tell me once the app record exists and I'll take it the rest of the way automatically: paste in
   the metadata above, upload screenshots (one 6.9" is ready in `AppStoreScreenshots/`, I can generate
   more), upload the signed IPA, set pricing to Free, fill the age rating and privacy questionnaires,
   attach the build to the version, and submit for review.
