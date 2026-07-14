import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import {
  DroneKind, PlayerDoc, ListingDoc,
  MIN_LISTING_PRICE, MAX_LISTING_PRICE, MARKETPLACE_FEE_FRACTION,
} from "./types";

const db = () => getFirestore();

/**
 * Lists an OWNED drone for sale. The drone is held in escrow the moment the listing goes active —
 * ownership is deducted from the seller immediately (not just on sale), so a seller can't list the
 * same drone twice or keep using a drone they've already put up for sale. Cancelling returns it.
 */
export const createListing = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const droneKind = String(request.data?.droneKind ?? "") as DroneKind;
  const priceCrystals = Math.floor(Number(request.data?.priceCrystals ?? 0));

  if (!["interceptor", "aegis", "harvester"].includes(droneKind)) {
    throw new HttpsError("invalid-argument", "Invalid droneKind.");
  }
  if (priceCrystals < MIN_LISTING_PRICE || priceCrystals > MAX_LISTING_PRICE) {
    throw new HttpsError("invalid-argument", `Price must be between ${MIN_LISTING_PRICE} and ${MAX_LISTING_PRICE} Crystals.`);
  }

  const playerRef = db().collection("players").doc(uid);
  const listingRef = db().collection("listings").doc();

  await db().runTransaction(async (tx) => {
    const playerSnap = await tx.get(playerRef);
    if (!playerSnap.exists) throw new HttpsError("failed-precondition", "Player profile missing.");
    const player = playerSnap.data() as PlayerDoc;
    const drone = player.drones[droneKind];

    if (!drone?.owned) throw new HttpsError("failed-precondition", "You don't own that drone.");
    // Selling the drone unequips it too — can't keep flying with a drone you no longer own.
    const equippedDrones = player.equippedDrones.filter((d) => d !== droneKind);

    const listing: ListingDoc = {
      id: listingRef.id,
      sellerUid: uid,
      droneKind,
      droneLevel: drone.level,
      priceCrystals,
      status: "active",
      createdAt: Date.now(),
    };
    tx.set(listingRef, listing);
    tx.update(playerRef, {
      [`drones.${droneKind}`]: { owned: false, level: 0 },
      equippedDrones,
    });
  });

  return { listingId: listingRef.id };
});

/** Cancels your own active listing and returns the escrowed drone. */
export const cancelListing = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  const listingId = String(request.data?.listingId ?? "");
  if (!listingId) throw new HttpsError("invalid-argument", "listingId is required.");

  const listingRef = db().collection("listings").doc(listingId);
  const playerRef = db().collection("players").doc(uid);

  await db().runTransaction(async (tx) => {
    const listingSnap = await tx.get(listingRef);
    if (!listingSnap.exists) throw new HttpsError("not-found", "Listing not found.");
    const listing = listingSnap.data() as ListingDoc;

    if (listing.sellerUid !== uid) throw new HttpsError("permission-denied", "Not your listing.");
    if (listing.status !== "active") throw new HttpsError("failed-precondition", "Listing is no longer active.");

    tx.update(listingRef, { status: "cancelled", resolvedAt: Date.now() });
    tx.update(playerRef, { [`drones.${listing.droneKind}`]: { owned: true, level: listing.droneLevel } });
  });

  return { ok: true };
});

/**
 * Buys an active listing. Atomic: deducts Crystals from the buyer, credits the seller minus a small
 * marketplace fee (a Crystal sink — otherwise the same pair of accounts could round-trip currency
 * indefinitely with no economic cost), and transfers the drone. A buyer who already owns that drone
 * kind is blocked (this is a single-copy-per-kind economy, not a stacking one).
 */
export const purchaseListing = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const buyerUid = request.auth.uid;
  const listingId = String(request.data?.listingId ?? "");
  if (!listingId) throw new HttpsError("invalid-argument", "listingId is required.");

  const listingRef = db().collection("listings").doc(listingId);
  const buyerRef = db().collection("players").doc(buyerUid);

  await db().runTransaction(async (tx) => {
    const listingSnap = await tx.get(listingRef);
    if (!listingSnap.exists) throw new HttpsError("not-found", "Listing not found.");
    const listing = listingSnap.data() as ListingDoc;

    if (listing.status !== "active") throw new HttpsError("failed-precondition", "Listing is no longer active.");
    if (listing.sellerUid === buyerUid) throw new HttpsError("invalid-argument", "Cannot buy your own listing.");

    const buyerSnap = await tx.get(buyerRef);
    if (!buyerSnap.exists) throw new HttpsError("failed-precondition", "Player profile missing.");
    const buyer = buyerSnap.data() as PlayerDoc;

    if (buyer.crystals < listing.priceCrystals) throw new HttpsError("failed-precondition", "Not enough Crystals.");
    if (buyer.drones[listing.droneKind]?.owned) throw new HttpsError("failed-precondition", "You already own this drone.");

    const sellerRef = db().collection("players").doc(listing.sellerUid);
    const fee = Math.floor(listing.priceCrystals * MARKETPLACE_FEE_FRACTION);
    const sellerProceeds = listing.priceCrystals - fee;

    tx.update(listingRef, { status: "sold", buyerUid, resolvedAt: Date.now() });
    tx.update(buyerRef, {
      crystals: FieldValue.increment(-listing.priceCrystals),
      [`drones.${listing.droneKind}`]: { owned: true, level: listing.droneLevel },
    });
    tx.update(sellerRef, { crystals: FieldValue.increment(sellerProceeds) });
  });

  return { ok: true };
});
