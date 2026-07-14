import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { computeAttackPower, computeDefensePower } from "./stats";
import { AttackDoc, PlayerDoc, ATTACK_SHIELD_MS, MAX_LOOT_FRACTION } from "./types";

const db = () => getFirestore();

/**
 * Resolves a casual (non-war) PvP raid: attacker vs defender's CURRENT server-stored stats — never
 * the client's self-reported power, which is exactly what a cheater would fake. Outcome is a weighted
 * coin-flip biased by the power ratio (not a hard threshold), so a stronger fleet is favored but never
 * guaranteed — keeps raiding meaningful without making underdogs feel it's pointless to try.
 */
export const attackPlayer = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const attackerUid = request.auth.uid;
  const defenderUid = String(request.data?.defenderUid ?? "");
  if (!defenderUid) throw new HttpsError("invalid-argument", "defenderUid is required.");
  if (defenderUid === attackerUid) throw new HttpsError("invalid-argument", "Cannot attack yourself.");

  const attackerRef = db().collection("players").doc(attackerUid);
  const defenderRef = db().collection("players").doc(defenderUid);

  const result = await db().runTransaction(async (tx) => {
    const [attackerSnap, defenderSnap] = await Promise.all([tx.get(attackerRef), tx.get(defenderRef)]);
    if (!attackerSnap.exists) throw new HttpsError("failed-precondition", "Attacker profile missing.");
    if (!defenderSnap.exists) throw new HttpsError("not-found", "Target not found.");

    const attacker = attackerSnap.data() as PlayerDoc;
    const defender = defenderSnap.data() as PlayerDoc;

    if (defender.lastAttackedAt && Date.now() - defender.lastAttackedAt < ATTACK_SHIELD_MS) {
      throw new HttpsError("failed-precondition", "Target is shielded from a recent attack.");
    }

    const attackerPower = computeAttackPower(attacker);
    const defenderPower = computeDefensePower(defender);

    // Logistic-style win probability from the power ratio, clamped so neither side is ever a sure
    // thing — e.g. a 3x power advantage is heavily favored (~85%) but not guaranteed.
    const ratio = attackerPower / Math.max(1, attackerPower + defenderPower);
    const winProbability = Math.min(0.92, Math.max(0.08, ratio));
    const didWin = Math.random() < winProbability;

    const crystalsLooted = didWin
      ? Math.min(defender.crystals, Math.floor(defender.crystals * MAX_LOOT_FRACTION))
      : 0;

    const now = Date.now();
    const attackDoc: AttackDoc = {
      attackerUid,
      defenderUid,
      attackerPower,
      defenderPower,
      outcome: didWin ? "win" : "loss",
      crystalsLooted,
      timestamp: now,
    };

    const attackRef = db().collection("attacks").doc();
    tx.set(attackRef, attackDoc);
    tx.update(defenderRef, { lastAttackedAt: now, lastActive: FieldValue.serverTimestamp() });
    if (crystalsLooted > 0) {
      tx.update(attackerRef, { crystals: FieldValue.increment(crystalsLooted) });
      tx.update(defenderRef, { crystals: FieldValue.increment(-crystalsLooted) });
    }

    return attackDoc;
  });

  return result;
});
