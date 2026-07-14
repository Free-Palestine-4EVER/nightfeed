import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { computeAttackPower, computeDefensePower } from "./stats";
import { AllianceDoc, PlayerDoc, WarDoc, WarAttackDoc, WAR_DURATION_MS } from "./types";

const db = () => getFirestore();

/** Only an alliance's leader can declare war, and only if neither side is already in one. */
export const declareWar = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const opponentAllianceId = String(request.data?.opponentAllianceId ?? "");
  if (!opponentAllianceId) throw new HttpsError("invalid-argument", "opponentAllianceId is required.");

  const playerRef = db().collection("players").doc(uid);
  const playerSnap = await playerRef.get();
  if (!playerSnap.exists) throw new HttpsError("failed-precondition", "Player profile missing.");
  const player = playerSnap.data() as PlayerDoc;
  if (!player.allianceId) throw new HttpsError("failed-precondition", "Not in an alliance.");
  if (player.allianceId === opponentAllianceId) throw new HttpsError("invalid-argument", "Cannot war your own alliance.");

  const ownAllianceRef = db().collection("alliances").doc(player.allianceId);
  const opponentRef = db().collection("alliances").doc(opponentAllianceId);
  const warRef = db().collection("wars").doc();

  await db().runTransaction(async (tx) => {
    const [ownSnap, opponentSnap] = await Promise.all([tx.get(ownAllianceRef), tx.get(opponentRef)]);
    if (!ownSnap.exists || !opponentSnap.exists) throw new HttpsError("not-found", "Alliance not found.");

    const own = ownSnap.data() as AllianceDoc;
    const opponent = opponentSnap.data() as AllianceDoc;

    if (own.leaderUid !== uid) throw new HttpsError("permission-denied", "Only the alliance leader can declare war.");
    if (own.activeWarId) throw new HttpsError("failed-precondition", "Your alliance is already at war.");
    if (opponent.activeWarId) throw new HttpsError("failed-precondition", "That alliance is already at war.");

    const now = Date.now();
    const war: WarDoc = {
      id: warRef.id,
      allianceA: own.id,
      allianceB: opponent.id,
      scoreA: 0,
      scoreB: 0,
      status: "active",
      startTime: now,
      endTime: now + WAR_DURATION_MS,
    };
    tx.set(warRef, war);
    tx.update(ownAllianceRef, { activeWarId: warRef.id });
    tx.update(opponentRef, { activeWarId: warRef.id });
  });

  return { warId: warRef.id };
});

/**
 * Attacks a member of the opposing alliance within an active war. Same server-authoritative power
 * computation and win-probability model as the casual attackPlayer raid, but scores stars toward the
 * war instead of looting crystals (wars are about alliance standing, not personal crystal gain).
 */
export const warAttack = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const attackerUid = request.auth.uid;
  const warId = String(request.data?.warId ?? "");
  const defenderUid = String(request.data?.defenderUid ?? "");
  if (!warId || !defenderUid) throw new HttpsError("invalid-argument", "warId and defenderUid are required.");

  const warRef = db().collection("wars").doc(warId);
  const attackerRef = db().collection("players").doc(attackerUid);
  const defenderRef = db().collection("players").doc(defenderUid);

  const result = await db().runTransaction(async (tx) => {
    const [warSnap, attackerSnap, defenderSnap] = await Promise.all([
      tx.get(warRef), tx.get(attackerRef), tx.get(defenderRef),
    ]);
    if (!warSnap.exists) throw new HttpsError("not-found", "War not found.");
    if (!attackerSnap.exists || !defenderSnap.exists) throw new HttpsError("failed-precondition", "Player profile missing.");

    const war = warSnap.data() as WarDoc;
    const attacker = attackerSnap.data() as PlayerDoc;
    const defender = defenderSnap.data() as PlayerDoc;

    if (war.status !== "active") throw new HttpsError("failed-precondition", "This war has ended.");
    if (Date.now() > war.endTime) throw new HttpsError("failed-precondition", "This war's time has expired.");

    let attackerSide: "A" | "B";
    let defenderExpectedAlliance: string;
    if (attacker.allianceId === war.allianceA && defender.allianceId === war.allianceB) {
      attackerSide = "A";
      defenderExpectedAlliance = war.allianceB;
    } else if (attacker.allianceId === war.allianceB && defender.allianceId === war.allianceA) {
      attackerSide = "B";
      defenderExpectedAlliance = war.allianceA;
    } else {
      throw new HttpsError("permission-denied", "Both players must belong to the warring alliances, on opposite sides.");
    }
    void defenderExpectedAlliance;

    const attackerPower = computeAttackPower(attacker);
    const defenderPower = computeDefensePower(defender);
    const ratio = attackerPower / Math.max(1, attackerPower + defenderPower);
    const winProbability = Math.min(0.92, Math.max(0.08, ratio));
    const roll = Math.random();

    // 0-3 stars, same shape as most base-raid war games: a clear win at high probability margin
    // earns full stars, a narrow win earns fewer, a loss earns none.
    let starsEarned = 0;
    if (roll < winProbability * 0.5) starsEarned = 3;
    else if (roll < winProbability) starsEarned = 2;
    else if (roll < winProbability + 0.15) starsEarned = 1;

    const attackDoc: WarAttackDoc = {
      attackerUid,
      defenderUid,
      side: attackerSide,
      starsEarned,
      attackerPower,
      defenderPower,
      timestamp: Date.now(),
    };

    tx.set(warRef.collection("attacks").doc(), attackDoc);
    if (starsEarned > 0) {
      tx.update(warRef, attackerSide === "A"
        ? { scoreA: FieldValue.increment(starsEarned) }
        : { scoreB: FieldValue.increment(starsEarned) });
    }

    return attackDoc;
  });

  return result;
});

/** Runs hourly; closes any war whose endTime has passed and clears both alliances' activeWarId. */
export const endExpiredWars = onSchedule("every 60 minutes", async () => {
  const now = Date.now();
  const expiredSnap = await db().collection("wars")
    .where("status", "==", "active")
    .where("endTime", "<=", now)
    .get();

  for (const doc of expiredSnap.docs) {
    const war = doc.data() as WarDoc;
    const batch = db().batch();
    batch.update(doc.ref, { status: "ended" });
    batch.update(db().collection("alliances").doc(war.allianceA), { activeWarId: null });
    batch.update(db().collection("alliances").doc(war.allianceB), { activeWarId: null });
    await batch.commit();
  }
});
