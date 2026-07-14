import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { AllianceDoc, PlayerDoc, MAX_ALLIANCE_MEMBERS } from "./types";

const db = () => getFirestore();

/**
 * Creates a new alliance with the caller as leader and sole starting member. One alliance per
 * player at a time (must leave the current one first) — enforced inside the transaction, not just
 * checked-then-written, to avoid a race where a player creates two alliances from two rapid taps.
 */
export const createAlliance = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const name = String(request.data?.name ?? "").trim();
  const tag = String(request.data?.tag ?? "").trim().toUpperCase();

  if (name.length < 3 || name.length > 24) {
    throw new HttpsError("invalid-argument", "Alliance name must be 3-24 characters.");
  }
  if (tag.length < 2 || tag.length > 5 || !/^[A-Z0-9]+$/.test(tag)) {
    throw new HttpsError("invalid-argument", "Tag must be 2-5 letters/numbers.");
  }

  const playerRef = db().collection("players").doc(uid);
  const allianceRef = db().collection("alliances").doc();

  await db().runTransaction(async (tx) => {
    const playerSnap = await tx.get(playerRef);
    if (!playerSnap.exists) throw new HttpsError("failed-precondition", "Player profile missing.");
    const player = playerSnap.data() as PlayerDoc;
    if (player.allianceId) throw new HttpsError("failed-precondition", "Already in an alliance — leave it first.");

    const alliance: AllianceDoc = {
      id: allianceRef.id,
      name,
      tag,
      leaderUid: uid,
      memberUids: [uid],
      memberCount: 1,
      totalPower: player.attackPower + player.defensePower,
      isOpen: true,
      activeWarId: null,
      createdAt: Date.now(),
    };
    tx.set(allianceRef, alliance);
    tx.update(playerRef, { allianceId: allianceRef.id });
  });

  return { allianceId: allianceRef.id };
});

export const joinAlliance = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const allianceId = String(request.data?.allianceId ?? "");
  if (!allianceId) throw new HttpsError("invalid-argument", "allianceId is required.");

  const playerRef = db().collection("players").doc(uid);
  const allianceRef = db().collection("alliances").doc(allianceId);

  await db().runTransaction(async (tx) => {
    const [playerSnap, allianceSnap] = await Promise.all([tx.get(playerRef), tx.get(allianceRef)]);
    if (!playerSnap.exists) throw new HttpsError("failed-precondition", "Player profile missing.");
    if (!allianceSnap.exists) throw new HttpsError("not-found", "Alliance not found.");

    const player = playerSnap.data() as PlayerDoc;
    const alliance = allianceSnap.data() as AllianceDoc;

    if (player.allianceId) throw new HttpsError("failed-precondition", "Already in an alliance — leave it first.");
    if (!alliance.isOpen) throw new HttpsError("permission-denied", "This alliance isn't accepting members.");
    if (alliance.memberCount >= MAX_ALLIANCE_MEMBERS) throw new HttpsError("resource-exhausted", "Alliance is full.");

    tx.update(allianceRef, {
      memberUids: FieldValue.arrayUnion(uid),
      memberCount: FieldValue.increment(1),
      totalPower: FieldValue.increment(player.attackPower + player.defensePower),
    });
    tx.update(playerRef, { allianceId });
  });

  return { ok: true };
});

export const leaveAlliance = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;

  const playerRef = db().collection("players").doc(uid);

  await db().runTransaction(async (tx) => {
    const playerSnap = await tx.get(playerRef);
    if (!playerSnap.exists) throw new HttpsError("failed-precondition", "Player profile missing.");
    const player = playerSnap.data() as PlayerDoc;
    if (!player.allianceId) throw new HttpsError("failed-precondition", "Not currently in an alliance.");

    const allianceRef = db().collection("alliances").doc(player.allianceId);
    const allianceSnap = await tx.get(allianceRef);
    if (!allianceSnap.exists) {
      // Alliance already gone somehow — just clear the dangling reference.
      tx.update(playerRef, { allianceId: null });
      return;
    }
    const alliance = allianceSnap.data() as AllianceDoc;
    const remaining = alliance.memberUids.filter((m) => m !== uid);

    if (remaining.length === 0) {
      tx.delete(allianceRef);
    } else {
      const nextLeader = alliance.leaderUid === uid ? remaining[0] : alliance.leaderUid;
      tx.update(allianceRef, {
        memberUids: FieldValue.arrayRemove(uid),
        memberCount: FieldValue.increment(-1),
        totalPower: FieldValue.increment(-(player.attackPower + player.defensePower)),
        leaderUid: nextLeader,
      });
    }
    tx.update(playerRef, { allianceId: null });
  });

  return { ok: true };
});
