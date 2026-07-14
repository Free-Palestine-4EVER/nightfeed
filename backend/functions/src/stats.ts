import { DroneKind, PlayerDoc } from "./types";

// Server-authoritative power computation — mirrors EmpireStore.attackPower/defensePower in
// NightFeed/Systems/EmpireStore.swift EXACTLY. This is deliberately duplicated rather than trusted
// from the client: attack/defense power determines PvP and war outcomes and crystal loot, so it must
// always be recomputed here from the player's actual stored stats, never read off a client-submitted
// value. If you tune the client formula, tune this one identically in the same change.

export function computeAttackPower(player: Pick<PlayerDoc, "weaponLevel" | "equippedDrones">): number {
  const interceptorCount = player.equippedDrones.filter((d: DroneKind) => d === "interceptor").length;
  return player.weaponLevel * 12 + interceptorCount * 40;
}

export function computeDefensePower(player: Pick<PlayerDoc, "shieldLevel" | "hullLevel" | "equippedDrones">): number {
  const aegisCount = player.equippedDrones.filter((d: DroneKind) => d === "aegis").length;
  return player.shieldLevel * 10 + player.hullLevel * 6 + aegisCount * 35;
}
