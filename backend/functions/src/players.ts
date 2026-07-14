import { onCall, HttpsError } from "firebase-functions/v2/https";
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
 * Ensures the caller's Firestore profile exists, creating it with defaults on first call. Called by
 * FirebaseManager.swift right after every sign-in (not just the first one — idempotent, a no-op once
 * the doc exists). Deliberately a plain callable rather than a beforeUserCreated blocking trigger:
 * blocking triggers need Identity Platform explicitly configured in the Firebase console, which is an
 * extra manual step this doesn't need — a callable works immediately on any project with Auth enabled.
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
