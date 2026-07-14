import { onCall, HttpsError } from "firebase-functions/v2/https";
import { beforeUserCreated } from "firebase-functions/v2/identity";
import { getFirestore } from "firebase-admin/firestore";
import { DroneKind, PlayerDoc, DRONE_KINDS } from "./types";

function defaultPlayerDoc(uid: string, displayName: string): PlayerDoc {
  const drones = {} as Record<DroneKind, { owned: boolean; level: number }>;
  for (const kind of DRONE_KINDS) drones[kind] = { owned: false, level: 0 };

  const now = Date.now();
  return {
    uid,
    displayName,
    crystals: 0,
    hullLevel: 0,
    weaponLevel: 0,
    shieldLevel: 0,
    drones,
    equippedDrones: [],
    unlockedPlanets: ["emberwatch"],
    selectedPlanet: "emberwatch",
    allianceId: null,
    attackPower: 0,
    defensePower: 0,
    lastAttackedAt: null,
    createdAt: now,
    lastActive: now,
  };
}

/**
 * Fires on Firebase Auth account creation (anonymous or Sign in with Apple) — seeds the player's
 * Firestore profile with defaults so every other function can assume a players/{uid} doc exists.
 */
export const onPlayerCreated = beforeUserCreated(async (event) => {
  const uid = event.data?.uid;
  if (!uid) return;
  const db = getFirestore();
  const ref = db.collection("players").doc(uid);
  const existing = await ref.get();
  if (existing.exists) return;
  await ref.set(defaultPlayerDoc(uid, "Captain"));
});

/**
 * Callable fallback: if a client somehow reaches the app before onPlayerCreated has propagated (or
 * during local emulator testing where auth triggers can lag), this lets the client explicitly ensure
 * its own profile exists. Idempotent — a no-op if the doc is already there.
 */
export const ensurePlayerProfile = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const db = getFirestore();
  const ref = db.collection("players").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set(defaultPlayerDoc(uid, "Captain"));
  }
  return { ok: true };
});
