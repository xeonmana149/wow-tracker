import type { SupabaseClient } from "@supabase/supabase-js";
import { iconUrlForFileId } from "./icons";

export type ParsedTraitNode = {
  entryID?: number;
  name?: string;
  tree?: string;
  rank: number;
  maxRank?: number;
};

export type ParsedExport = {
  meta?: { exportedAt?: string };
  basic?: {
    level?: number;
    money?: number;
    guild?: string | null;
  };
  stats?: {
    maxHealth?: number;
    maxMana?: number;
    moveSpeedPercent?: number;
    strength?: number;
    agility?: number;
    intellect?: number;
    stamina?: number;
    spirit?: number;
    attackPower?: number;
    critChancePercent?: number;
    dodgeChancePercent?: number;
    parryChancePercent?: number;
    armor?: number;
    defense?: number;
    mainHandMin?: number;
    mainHandMax?: number;
    resistances?: {
      arcane?: number;
      fire?: number;
      frost?: number;
      nature?: number;
      shadow?: number;
    };
  };
  professions?: { name: string; skill: number; maxSkill?: number }[];
  gear?: Record<string, { link: string; name: string; color?: string; icon?: number; tooltip?: string[] }>;
  traits?: {
    experimental?: boolean;
    error?: string;
    configs?: { configID: number; nodes: ParsedTraitNode[] }[];
  };
};

// Addon gear key -> the site's Equipped Gear slot name. "shirt" and
// "tabard" aren't tracked, so they're left out on purpose.
const GEAR_SLOT_MAP: Record<string, string> = {
  head: "Head",
  neck: "Neck",
  shoulder: "Shoulders",
  back: "Back",
  chest: "Chest",
  wrist: "Wrists",
  hands: "Hands",
  waist: "Waist",
  legs: "Legs",
  feet: "Feet",
  finger1: "Ring 1",
  finger2: "Ring 2",
  trinket1: "Trinket 1",
  trinket2: "Trinket 2",
  mainHand: "Main Hand",
  offHand: "Off Hand",
  ranged: "Ranged / Relic",
};

// Maps a site stat key to how to pull the matching number out of the addon
// export. Only stats the addon actually reads are listed here - anything
// not covered here (weapon damage range, hit%, Defense) is left alone so an
// import never overwrites what you've typed in by hand for those.
const STAT_MAP: Record<string, (d: ParsedExport) => number | null | undefined> = {
  max_health: (d) => d.stats?.maxHealth,
  max_mana: (d) => d.stats?.maxMana,
  movement_speed: (d) =>
    d.stats?.moveSpeedPercent && d.stats.moveSpeedPercent > 0 ? d.stats.moveSpeedPercent : null,
  strength: (d) => d.stats?.strength,
  agility: (d) => d.stats?.agility,
  intellect: (d) => d.stats?.intellect,
  stamina: (d) => d.stats?.stamina,
  spirit: (d) => d.stats?.spirit,
  attack_power: (d) => d.stats?.attackPower,
  crit_strike: (d) => d.stats?.critChancePercent,
  dodge: (d) => d.stats?.dodgeChancePercent,
  parry: (d) => d.stats?.parryChancePercent,
  armor: (d) => d.stats?.armor,
  defense: (d) => d.stats?.defense,
  main_hand_min: (d) => d.stats?.mainHandMin,
  main_hand_max: (d) => d.stats?.mainHandMax,
  res_arcane: (d) => d.stats?.resistances?.arcane,
  res_fire: (d) => d.stats?.resistances?.fire,
  res_frost: (d) => d.stats?.resistances?.frost,
  res_nature: (d) => d.stats?.resistances?.nature,
  res_shadow: (d) => d.stats?.resistances?.shadow,
};

const MAX_SKILL = 300;

export type ImportResult = {
  gearChanges: string[];
  talentApplied: string[];
  talentUnknown: string[];
};

// Applies a parsed addon export to a character's rows. Shared between the
// browser Import panel (the normal anon-key client, checked by RLS as the
// logged-in owner) and the auto-sync API route (the service-role client,
// since a companion app running on your PC has no browser login session -
// its sync_token is what proves it's allowed to write instead). The import
// steps themselves are identical either way.
export async function applyImport(
  supabase: SupabaseClient,
  characterId: string,
  activeSpec: number,
  professions: { id: string; profession: string; skill: number }[],
  parsed: ParsedExport
): Promise<ImportResult> {
  // 1. Character-level fields.
  const charUpdate: Record<string, number | string> = {};
  if (typeof parsed.basic?.level === "number") charUpdate.level = parsed.basic.level;
  if (typeof parsed.basic?.money === "number") charUpdate.money_copper = parsed.basic.money;
  if (parsed.basic?.guild) charUpdate.guild = parsed.basic.guild;

  if (Object.keys(charUpdate).length > 0) {
    const { error } = await supabase.from("characters").update(charUpdate).eq("id", characterId);
    if (error) throw new Error(error.message);
  }

  // 2. Stats.
  const statRows = Object.entries(STAT_MAP)
    .map(([stat, get]) => ({ stat, value: get(parsed) }))
    .filter((r): r is { stat: string; value: number } => typeof r.value === "number")
    .map((r) => ({ character_id: characterId, stat: r.stat, value: r.value }));

  if (statRows.length > 0) {
    const { error } = await supabase
      .from("character_stats")
      .upsert(statRows, { onConflict: "character_id,stat" });
    if (error) throw new Error(error.message);
  }

  // 3. Professions - update ones you already track, add ones you don't yet.
  for (const p of parsed.professions ?? []) {
    const skill = Math.min(MAX_SKILL, Math.max(1, p.skill || 1));
    const existing = professions.find(
      (x) => x.profession.toLowerCase() === p.name.toLowerCase()
    );
    if (existing) {
      if (existing.skill !== skill) {
        await supabase.from("character_professions").update({ skill }).eq("id", existing.id);
      }
    } else {
      await supabase.from("character_professions").insert({
        character_id: characterId,
        profession: p.name,
        skill,
      });
    }
  }

  // 4. Equipped gear - upsert whatever's filled, and clear out any tracked
  //    slot that's no longer present in the export (i.e. you unequipped it).
  const gearRows: {
    character_id: string;
    slot: string;
    item_name: string;
    item_link: string;
    item_quality: string | null;
    item_icon: string | null;
    tooltip: string[];
    updated_at: string;
  }[] = [];
  const emptySlots: string[] = [];
  for (const [addonSlot, siteSlot] of Object.entries(GEAR_SLOT_MAP)) {
    const item = parsed.gear?.[addonSlot];
    if (!item) {
      emptySlots.push(siteSlot);
      continue;
    }
    gearRows.push({
      character_id: characterId,
      slot: siteSlot,
      item_name: item.name,
      item_link: item.link,
      item_quality: item.color ?? null,
      item_icon: iconUrlForFileId(item.icon),
      tooltip: item.tooltip ?? [],
      updated_at: new Date().toISOString(),
    });
  }

  if (gearRows.length > 0) {
    const { error } = await supabase
      .from("equipped_gear")
      .upsert(gearRows, { onConflict: "character_id,slot" });
    if (error) throw new Error(error.message);
  }

  if (emptySlots.length > 0) {
    const { error } = await supabase
      .from("equipped_gear")
      .delete()
      .eq("character_id", characterId)
      .in("slot", emptySlots);
    if (error) throw new Error(error.message);
  }

  // 5. Talents - only nodes the addon already resolved a name and tree for

  // 5. Talents - only nodes the addon already resolved a name and tree for
  //    get written into the planner. Unresolved ones stay reference-only.
  const talentApplied: string[] = [];
  const talentUnknown: string[] = [];
  for (const cfg of parsed.traits?.configs ?? []) {
    for (const node of cfg.nodes) {
      if (node.name && node.tree) {
        const { error } = await supabase.from("character_talents").upsert(
          {
            character_id: characterId,
            slot: activeSpec,
            tree: node.tree,
            talent: node.name,
            rank: node.rank,
          },
          { onConflict: "character_id,slot,tree,talent" }
        );
        if (!error) {
          talentApplied.push(`${node.name} ${node.rank}/${node.maxRank ?? node.rank}`);
        }
      } else {
        talentUnknown.push(
          `entryID ${node.entryID ?? "?"} (${node.rank}/${node.maxRank ?? node.rank})`
        );
      }
    }
  }

  return {
    gearChanges: gearRows.map((r) => `${r.slot}: ${r.item_name}`),
    talentApplied,
    talentUnknown,
  };
}