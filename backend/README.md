# NIGHTFEED Starfleet backend

Real Firebase backend for the alliance / clan war / PvP meta-layer: accounts, alliances, clan wars,
and server-authoritative attack resolution. Everything that touches currency, stats, alliance
membership, or combat outcomes runs through Cloud Functions — the client can never write those
fields directly (see `firestore.rules`), so there's no client-side value a player could edit to cheat.

## What's built

- `firestore.rules` — locks every sensitive field to Cloud-Functions-only writes; clients can only
  read and edit their own `displayName`.
- `firestore.indexes.json` — composite indexes for the leaderboard/matchmaking-style queries.
- `functions/src/players.ts` — seeds a `players/{uid}` profile on account creation.
- `functions/src/alliances.ts` — `createAlliance` / `joinAlliance` / `leaveAlliance`, transactional
  (no race where a rapid double-tap creates two alliances or double-joins).
- `functions/src/attacks.ts` — `attackPlayer`: casual PvP raid. Recomputes both players' attack/
  defense power **server-side** from their stored stats (never trusts a client-submitted value),
  resolves a probabilistic win/loss weighted by the power ratio, loots up to 12% of the defender's
  crystals on a win, and grants the defender an 8-hour shield from further raids.
- `functions/src/wars.ts` — `declareWar` (leader-only, one war per alliance at a time),
  `warAttack` (same server-authoritative resolution, scores 0-3 stars per hit), and a scheduled
  `endExpiredWars` function that closes wars past their 24h window every hour.
- `functions/src/stats.ts` — the server-side attack/defense power formula. **Must stay numerically
  identical to `EmpireStore.attackPower`/`defensePower` in the iOS app** (`NightFeed/Systems/
  EmpireStore.swift`) — if you tune one, tune the other the same way in the same change.

TypeScript compiles clean (`npx tsc` in `functions/`, zero errors) as of this write-up.

## Still to do before this is live

1. **You need to authenticate the Firebase CLI** — this can't be done headlessly (it's a browser
   OAuth flow). Run `firebase login` yourself, then tell me it's done.
2. **Create the Firebase project** (or point at an existing one if you already have a Google Cloud /
   Firebase account you want to use — several of your other apps already use Firebase, so you may
   already have a project worth reusing). Once you've logged in, I'll run `firebase init` /
   `firebase use --add` here and wire up `.firebaserc`.
3. **Enable Firestore + Authentication** (Anonymous sign-in method, at minimum — Sign in with Apple
   can be added later for cross-device account recovery) in the Firebase console for that project.
4. **Deploy**: `cd backend && firebase deploy --only firestore:rules,firestore:indexes,functions`.
5. **Add the Firebase iOS SDK** to the Xcode project (Swift Package Manager) and drop in the real
   `GoogleService-Info.plist` from the Firebase console — I'll do this the moment the project exists.
6. **IAP product IDs** (`com.loom.nightfeed.crystals.pouch/satchel/chest/hoard/vault`) still need to
   be created as Consumable in-app purchases in App Store Connect — same category of manual step as
   the AdMob ad units and the app record itself (Apple's API can't create these either).

## Local testing (once logged in)

`cd backend/functions && npm run serve` starts the Firebase emulator suite (Auth + Firestore +
Functions) so the full alliance/war/attack flow can be tested end-to-end without touching production
data or spending a real deploy cycle.
