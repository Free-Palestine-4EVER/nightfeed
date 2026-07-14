# NIGHTFEED — Reddit launch posts

Two variants: a launch post for gameplay-focused subreddits (r/iosgaming etc.) and a shorter
dev-diary variant for r/gamedev / r/devblogs. Swap `[APP STORE LINK]` for the real link once the
app record is live.

---

## 1. r/iosgaming (or similar gameplay-focused subs)

**Title:**

> Made a Vampire Survivors-style game for iOS — drag to move, everything else auto-fires. Free, out now.

**Body:**

I've spent the last few weeks building NIGHTFEED, a top-down survivor-roguelite for iPhone. If you've played Vampire Survivors you know the loop: you drag your finger to move, your weapons fire on their own at whatever's closest, and every time you level up you pick one of three upgrade cards. No aiming, no buttons to mash — the whole game is "where do I stand" and "what do I pick."

The part I spent the most time on is the escalation curve. A lot of games in this genre either throw everything at you in the first two minutes or stay flat and boring — I wanted a run that actually builds. Enemies ramp smoothly across an 18-minute run instead of spiking, and there's a scheduled mini-boss (the Nightmaw) that shows up on its own timer regardless of how the wave is going, so you can't just turtle and wait it out.

What's actually in it right now:

- **8 weapons** (6 base + 2 evolved forms) — Fang Bolt, Ember Orbit, Nova Pulse, Blood Lance, Bat Swarm, and Reaper Whirl each play completely differently; max the right weapon and passive together and it evolves into something stronger (Moonfang Barrage, Crimson Maelstrom)
- **4 enemy types** including the Nightmaw mini-boss on a timer
- A **level-up card system** — pick a new weapon, a passive, or (rarely) an evolution every time you level
- **Permanent progression** — gold from every run buys upgrades in a shop between runs: more health, more damage, a starting level boost, even a familiar that fights alongside you
- Every visual and every sound effect is generated in code, no bundled art assets

It's free, with optional ads — you can watch one to revive once per run or double your gold, but you're never blocked from playing if you skip them. No IAP, no energy system, no account to make.

Not asking anyone to do anything beyond taking a look — genuinely just want it in front of people who actually play this genre and would notice if the balance feels off. Happy to answer anything about how it's built too.

[APP STORE LINK]

---

## 2. r/gamedev or r/devblogs (dev-diary framing)

**Title:**

> Built a survivor-roguelite for iOS solo over a few weeks — native SpriteKit, zero bundled assets

**Body:**

Wanted to share the build side of a project I just finished: NIGHTFEED, a Vampire Survivors-style survivor-roguelite for iPhone, written in Swift + SpriteKit.

The constraint I set myself going in: no bundled image or audio assets at all. Every sprite, particle, UI element, and sound effect is generated in code at build/runtime — partly to keep the project genuinely solo-sized, partly so there's nothing that can go "missing" from the bundle. It forced some interesting tradeoffs, especially on the audio side (procedural SFX/music) and the app icon (also generated, not hand-drawn).

Performance-wise, the thing I cared about most was keeping hundreds of enemies on screen without hitching on-device. Two decisions did most of the work: everything (enemies, projectiles, XP gems, damage labels, particle emitters) is object-pooled, so nothing allocates or deallocates during a run, and collision is a manual spatial-grid distance check instead of SpriteKit's built-in physics — physics was the first thing that showed up in Instruments once enemy counts climbed, and a plain grid was both faster and easier to reason about.

Content-wise it's 6 weapons (each with a genuinely different attack pattern — orbiters, piercing, homing, melee whirl, AoE burst), 2 of which evolve into upgraded forms if you max the right weapon/passive combo, 4 enemy types plus a scheduled mini-boss, and a permanent meta-progression shop funded by gold from each run. It's free with optional rewarded/interstitial ads (revive once, double gold, capped at 1 interstitial per 3 completed runs) — no IAP, no forced ads on cold launch.

Happy to go into any of this in more detail — the pooling setup, the spatial grid, the procedural audio, whatever's useful. Mostly just wanted to put the process out there rather than only the launch announcement.

[APP STORE LINK]
