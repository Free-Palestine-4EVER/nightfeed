// Shared data-model types for the NIGHTFEED Starfleet backend. Mirrors the client's
// NightFeed/Systems/EmpireTypes.swift + EmpireStore.swift vocabulary — keep both in sync by hand
// (no shared codegen between Swift and TS in this project).

export type DroneKind = "interceptor" | "aegis" | "harvester";

export interface DroneState {
  owned: boolean;
  level: number;
}

export interface PlayerDoc {
  uid: string;
  displayName: string;
  crystals: number;
  hullLevel: number;
  weaponLevel: number;
  shieldLevel: number;
  drones: Record<DroneKind, DroneState>;
  equippedDrones: DroneKind[];
  unlockedPlanets: string[];
  selectedPlanet: string;
  allianceId: string | null;
  attackPower: number;
  defensePower: number;
  /** Epoch ms. Recently-attacked players get a brief revenge-shield — see ATTACK_SHIELD_MS. */
  lastAttackedAt: number | null;
  createdAt: number;
  lastActive: number;
}

export interface AllianceDoc {
  id: string;
  name: string;
  tag: string;
  leaderUid: string;
  memberUids: string[];
  memberCount: number;
  totalPower: number;
  isOpen: boolean;
  activeWarId: string | null;
  createdAt: number;
}

export interface WarDoc {
  id: string;
  allianceA: string;
  allianceB: string;
  scoreA: number;
  scoreB: number;
  status: "active" | "ended";
  startTime: number;
  endTime: number;
}

export interface WarAttackDoc {
  attackerUid: string;
  defenderUid: string;
  side: "A" | "B";
  starsEarned: number; // 0-3, like most base-raid war games
  attackerPower: number;
  defenderPower: number;
  timestamp: number;
}

export interface AttackDoc {
  attackerUid: string;
  defenderUid: string;
  attackerPower: number;
  defenderPower: number;
  outcome: "win" | "loss";
  crystalsLooted: number;
  timestamp: number;
}

export const DRONE_KINDS: DroneKind[] = ["interceptor", "aegis", "harvester"];

export const MAX_EQUIPPED_DRONES = 3;
export const MAX_SHIP_STAT_LEVEL = 20;
export const MAX_DRONE_LEVEL = 10;

/** How long a just-attacked player is shielded from further raids, to prevent grief-chaining. */
export const ATTACK_SHIELD_MS = 8 * 60 * 60 * 1000; // 8 hours

/** Max fraction of a defender's crystal balance a single raid can loot. */
export const MAX_LOOT_FRACTION = 0.12;

export const WAR_DURATION_MS = 24 * 60 * 60 * 1000; // 24 hours
export const MAX_ALLIANCE_MEMBERS = 30;
