import { initializeApp } from "firebase-admin/app";

initializeApp();

export { ensurePlayerProfile } from "./players";
export { createAlliance, joinAlliance, leaveAlliance } from "./alliances";
export { attackPlayer } from "./attacks";
export { declareWar, warAttack, endExpiredWars } from "./wars";
export { createListing, cancelListing, purchaseListing } from "./marketplace";
