import type { SupabaseClient } from "@supabase/supabase-js";
import { iconUrlForFileId, PRIMARY_PROFESSIONS } from "./icons";
import {
  ACHIEVEMENT_MESSAGE,
  awardAchievement,
  awardTier,
  tierMessage,
  isWithinFoundingWindow,
  computeCounter,
  TIERED_ACHIEVEMENT_KINDS,
  PERSONALITY_BADGES,
  LEVEL_MILESTONES,
  type AchievementKind,
  type TieredAchievementKind,
  type AchievementTier,
} from "./achievements";
import { checkAccountAchievements } from "./accountAchievements";
import { applyLiveObservation, ensureItemsExist } from "./items";

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
    name?: string;
    race?: string;
    class?: string;
    faction?: string;
    realm?: string;
    level?: number;
    money?: number;
    guild?: string | null;
    honor?: number;
    deaths?: number;
    pvpKills?: number;
    // XP within the character's CURRENT level (not toward the level cap) -
    // xpMax comes back 0 at the level cap, since there's no more bar left
    // to fill; the site treats that as "no live XP bar" rather than 0%.
    xp?: number;
    xpMax?: number;
    // Total time played, in seconds (2026-09-27, "Addicted" achievement).
    // Fetched by the addon via the async RequestTimePlayed()/TIME_PLAYED_MSG
    // pair, not part of the Statistics-pane sweep - see the addon's
    // collectBasic() and lib/achievements.ts's TieredAchievementKind
    // comment for why this is handled separately from every other tiered
    // achievement. Missing/undefined until that event has fired at least
    // once on the player's client.
    timePlayedSeconds?: number;
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
  // recipes is only ever present for a profession whose trade skill window
  // has actually been opened at least once since the addon started
  // tracking this - there's no API that can list known recipes without
  // that window being open, on either the old or new profession UI. When
  // it's missing, whatever recipes are already recorded from an earlier
  // sync are left untouched rather than being cleared.
  //
  // A recipe entry is a bare string on an addon build from before 1.3.0 (no
  // icon capture yet), a { name, icon, id } object on 1.3.0, or the fuller
  // shape below (reagents + tooltip text + quality color) from the version
  // after that - all normalized to one consistent object shape before
  // being stored, so the site never has to care which addon version a
  // given sync came from. `color` is a bare "rrggbb" hex string (no '#'),
  // read straight off the item's own rendered tooltip color in-game (same
  // trick already used for gear - see importLogic's gear color handling
  // below), since this server's items don't reliably carry quality any
  // other way.
  professions?: {
    name: string;
    skill: number;
    maxSkill?: number;
    recipes?: (
      | string
      | {
          name: string;
          icon?: number | string | null;
          id?: number;
          reagents?: {
            itemID: number;
            name: string;
            icon?: number | string | null;
            quantity: number;
            color?: string | null;
          }[];
          tooltip?: string[];
          color?: string | null;
        }
    )[];
  }[];
  gear?: Record<
    string,
    { link: string; name: string; id?: number; color?: string; icon?: number; tooltip?: string[] }
  >;
  // Every item seen in bags/bank on this sync - NOT stored per-character
  // anywhere (no bag-viewer feature exists or is planned), purely fed
  // through the same item-database pipeline as gear so items get real,
  // verified data before anyone's necessarily equipped them. See the
  // 2026-09-24 chat and addon 1.7.0's collectContainerItems().
  bagItems?: { id?: number; name: string; color?: string; icon?: number; tooltip?: string[] }[];
  traits?: {
    experimental?: boolean;
    error?: string;
    configs?: { configID: number; nodes: ParsedTraitNode[] }[];
  };
  // Every stat the in-game Statistics pane reports (Phase 1 of the
  // 2026-09-25 Statistics feature - see collectStatistics() in the addon).
  // Captured wholesale rather than a curated subset, so a future badge idea
  // never needs another addon update just to start tracking a stat that
  // wasn't grabbed before. value is already formatted by the client
  // ("1,502", or "--" for a stat never recorded) and stored as-is.
  statistics?: { id: number; category: string; name: string; value: string }[];
  // "Legacy Challenges" - the REAL Blizzard-server Achievements pane
  // (GetCategoryList/GetAchievementInfo/GetAchievementCriteriaInfo), a
  // completely separate system from the Statistics pane above. Confirmed
  // small (111 achievements/29 categories) via the addon's
  // `/wft achievementsprobe` diagnostic on 2026-09-27, so synced wholesale
  // rather than a curated subset - see collectLegacyAchievements() in the
  // addon. criteria is the per-achievement checklist (e.g. one entry per
  // required dungeon/zone), undefined for achievements with none.
  legacyAchievements?: {
    id: number;
    category: string;
    name: string;
    completed: boolean;
    description?: string;
    criteria?: { text: string; completed: boolean }[];
    // The achievement's own Blizzard icon fileID (addon 1.8.6+) - fed
    // through the same iconUrlForFileId() helper as item/gear icons
    // elsewhere on the site, so these read as real WoW achievement icons
    // rather than a generic placeholder. Undefined on exports from an
    // older addon version.
    icon?: number;
  }[];
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

type ActivityEvent = {
  character_id: string | null;
  user_id: string;
  kind:
    | "level_up"
    | "profession_maxed"
    | "character_created"
    | "epic_gear"
    | "gold_milestone"
    | "pvp_rank_up"
    | "achievement_earned";
  message: string;
  // Which specific achievement this row is about, and its tier if tiered -
  // only set on "achievement_earned" rows (2026-09-25), so the Activity
  // sidebar and Recent Activity can render the real badge art instead of a
  // generic icon. Left undefined (-> null in the DB) for every other kind,
  // and for the account-wide achievements below, which checkAccountAchievements
  // reports as plain strings with no achievement kind to attach.
  achievement_kind?: TieredAchievementKind | AchievementKind;
  achievement_tier?: AchievementTier | null;
};

// Epic and Legendary item-link quality colors (RRGGBB, as extractItemColor
// in the addon returns them).
const EPIC_COLOR = "a335ee";
const LEGENDARY_COLOR = "ff8000";
// Both together - treated as one "notable gear" narration event in the
// activity feed, even though the achievements they feed into differ (Epic
// counts toward a tiered badge, Legendary is its own one-off badge).
const NOTABLE_GEAR_COLORS = new Set([EPIC_COLOR, LEGENDARY_COLOR]);

// Gold amounts (in real gold, not copper) worth calling out per character.
const GOLD_MILESTONES = [100, 500, 1000, 5000];

// The level cap on this server - crossing it is what the "max level"
// achievement means.
const MAX_CHARACTER_LEVEL = 60;

// The professions this server treats as secondary (see the earlier
// correction: no Archaeology on this server, just these three) - used for
// the "Renaissance" achievement (every profession maxed on one character).
const SECONDARY_PROFESSIONS = ["First Aid", "Cooking", "Fishing"];

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
  // Read the character's own current values BEFORE anything below changes
  // them - this is what lets the activity feed notice a level-up or a
  // maxed profession, by comparing against what's about to be written.
  const { data: before, error: beforeError } = await supabase
    .from("characters")
    .select("id, name, level, user_id, money_copper, created_at")
    .eq("id", characterId)
    .single();

  if (beforeError || !before) {
    throw new Error("Character not found");
  }

  const events: ActivityEvent[] = [];

  // Founding Member - checked on every sync rather than just at creation,
  // so it still gets awarded retroactively to characters created before
  // this achievement existed. awardAchievement's own conflict handling
  // means this is harmless to call repeatedly.
  if (before.created_at && isWithinFoundingWindow(before.created_at)) {
    const earned = await awardAchievement(supabase, characterId, "founding_member");
    if (earned) {
      events.push({
        character_id: characterId,
        user_id: before.user_id,
        kind: "achievement_earned",
        achievement_kind: "founding_member",
        achievement_tier: null,
        message: ACHIEVEMENT_MESSAGE.founding_member(before.name),
      });
    }
  }

  // Character Created (2026-09-25) - replaces the old always-shown, always-
  // WoW-CDN-icon "Created <date>" badge that lived only in CharacterCard.tsx
  // with a real one-off achievement, so it goes through the same local-art/
  // BadgePlaceholder rendering as everything else and shows up on the
  // achievements page. Every character earns this, so it's unconditional -
  // same retroactive-on-every-sync pattern as Founding Member above, but
  // backdated to the character's REAL created_at (not whenever it happened
  // to get backfilled) so "when earned" stays meaningful. Only logged to
  // the activity feed for a character that was JUST created (within the
  // last few minutes) - otherwise backfilling every existing character the
  // first time they sync after this shipped would flood Recent Activity
  // with "was created!" events for characters that are actually old.
  if (before.created_at) {
    const createdEarned = await awardAchievement(
      supabase,
      characterId,
      "character_created",
      before.created_at
    );
    if (createdEarned) {
      const justCreated = Date.now() - new Date(before.created_at).getTime() < 5 * 60 * 1000;
      if (justCreated) {
        events.push({
          character_id: characterId,
          user_id: before.user_id,
          kind: "achievement_earned",
          achievement_kind: "character_created",
          achievement_tier: null,
          message: ACHIEVEMENT_MESSAGE.character_created(before.name),
        });
      }
    }
  }

  // 1. Character-level fields.
  const charUpdate: Record<string, number | string> = {};
  if (typeof parsed.basic?.level === "number") charUpdate.level = parsed.basic.level;
  if (typeof parsed.basic?.money === "number") charUpdate.money_copper = parsed.basic.money;
  if (parsed.basic?.guild) charUpdate.guild = parsed.basic.guild;
  // Confirmed via /wft probe that this server's client exposes the older
  // honor-as-a-resource-bar API (UnitHonor), so this is a real live value
  // from the addon now, not a manual field anymore.
  if (typeof parsed.basic?.honor === "number") charUpdate.honor_points = parsed.basic.honor;
  // Race and class don't realistically change once a character exists, but
  // keeping them synced from the addon (rather than only ever set once at
  // creation) means a wrong value never has to be hand-fixed - it just
  // corrects itself on the next sync.
  if (parsed.basic?.race) charUpdate.race = parsed.basic.race;
  if (parsed.basic?.class) charUpdate.class = parsed.basic.class;
  // Deaths and PvP kills are counters the addon keeps itself (nothing on
  // this server tracks them for us) - they only ever count up, so like
  // level/gold/honor it's always safe to overwrite with whatever the addon
  // last reported, never something to hand-edit.
  if (typeof parsed.basic?.deaths === "number") charUpdate.deaths = parsed.basic.deaths;
  if (typeof parsed.basic?.pvpKills === "number") charUpdate.pvp_kills = parsed.basic.pvpKills;
  // Live XP within the current level - see the ParsedExport type above for
  // why xpMax can legitimately be 0 (level cap, no bar left to fill).
  if (typeof parsed.basic?.xp === "number") charUpdate.xp = parsed.basic.xp;
  if (typeof parsed.basic?.xpMax === "number") charUpdate.xp_max = parsed.basic.xpMax;

  if (Object.keys(charUpdate).length > 0) {
    const { error } = await supabase.from("characters").update(charUpdate).eq("id", characterId);
    if (error) throw new Error(error.message);
  }

  if (typeof parsed.basic?.level === "number" && parsed.basic.level > before.level) {
    events.push({
      character_id: characterId,
      user_id: before.user_id,
      kind: "level_up",
      message: `${before.name} reached level ${parsed.basic.level}`,
    });

    if (parsed.basic.level >= MAX_CHARACTER_LEVEL) {
      const earned = await awardAchievement(supabase, characterId, "max_level");
      if (earned) {
        events.push({
          character_id: characterId,
          user_id: before.user_id,
          kind: "achievement_earned",
          achievement_kind: "max_level",
          achievement_tier: null,
          message: ACHIEVEMENT_MESSAGE.max_level(before.name),
        });
      }
    }

    // Level milestones - one-off callouts every 10 levels short of the cap
    // (2026-09-25), same "crossed a threshold this sync" shape as the gold
    // milestones below, but these ARE real achievements (via awardAchievement,
    // not just activity-feed narration), since the point is leveling up
    // feeling like it earns something the whole way to 60, not just at the
    // cap. awardAchievement's own (character_id, kind) conflict handling
    // means a sync that jumps straight past several milestones at once
    // (e.g. a rested-XP dungeon run taking someone from 8 to 24) still
    // correctly awards every one crossed, not just the highest.
    for (const milestone of LEVEL_MILESTONES) {
      if (before.level < milestone.level && parsed.basic.level >= milestone.level) {
        const milestoneEarned = await awardAchievement(supabase, characterId, milestone.kind);
        if (milestoneEarned) {
          events.push({
            character_id: characterId,
            user_id: before.user_id,
            kind: "achievement_earned",
            achievement_kind: milestone.kind,
            achievement_tier: null,
            message: ACHIEVEMENT_MESSAGE[milestone.kind](before.name),
          });
        }
      }
    }
  }

  // Gold milestones - fire once when a sync's new balance crosses a
  // threshold that the previous known balance hadn't reached yet. Uses
  // the "before" row read at the top of this function, so a single sync
  // can only ever cross each threshold once (no double-firing on a
  // future sync that stays above it). This is just activity-feed
  // narration off the live balance - the tiered "gold" ACHIEVEMENT is
  // separate and now sourced from the Statistics pane's lifetime "Total
  // gold acquired" instead (see the Statistics-based badges section
  // further down), so spending gold never takes that badge away.
  if (typeof parsed.basic?.money === "number") {
    const beforeCopper = before.money_copper ?? 0;
    const afterCopper = parsed.basic.money;
    for (const gold of GOLD_MILESTONES) {
      const thresholdCopper = gold * 10000;
      if (beforeCopper < thresholdCopper && afterCopper >= thresholdCopper) {
        events.push({
          character_id: characterId,
          user_id: before.user_id,
          kind: "gold_milestone",
          message: `${before.name} hit ${gold} gold`,
        });
      }
    }
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
  //    Also notes when a profession crosses the max-skill line for the
  //    first time, for the activity feed. `updatedProfessions` mirrors
  //    what's now in the database, so the Renaissance check below (which
  //    needs to see the character's FULL profession list, not just what
  //    this one sync touched) has an accurate picture to work from.
  const updatedProfessions = professions.map((p) => ({ ...p }));
  for (const p of parsed.professions ?? []) {
    const skill = Math.min(MAX_SKILL, Math.max(1, p.skill || 1));
    // Recipe entries from an older addon build (bare string, or missing
    // reagents/tooltip) are normalized to the one full shape everything
    // else uses, so the site never needs to branch on which addon version
    // a sync came from.
    const recipes = p.recipes?.map((r) =>
      typeof r === "string"
        ? { name: r }
        : {
            name: r.name,
            icon: r.icon ?? null,
            id: r.id,
            reagents: r.reagents,
            tooltip: r.tooltip,
            color: r.color ?? null,
          }
    );
    const existing = professions.find(
      (x) => x.profession.toLowerCase() === p.name.toLowerCase()
    );
    if (existing) {
      const profUpdate: Record<string, number | typeof recipes> = {};
      if (existing.skill !== skill) profUpdate.skill = skill;
      // Only touch recipes when the addon actually sent some for this sync
      // (meaning the trade skill window was opened) - otherwise leave
      // whatever's already recorded from an earlier visit alone.
      if (recipes && recipes.length > 0) profUpdate.recipes = recipes;
      if (Object.keys(profUpdate).length > 0) {
        await supabase.from("character_professions").update(profUpdate).eq("id", existing.id);
      }
      const tracked = updatedProfessions.find((x) => x.id === existing.id);
      if (tracked) tracked.skill = skill;

      if (skill >= MAX_SKILL && existing.skill < MAX_SKILL) {
        events.push({
          character_id: characterId,
          user_id: before.user_id,
          kind: "profession_maxed",
          message: `${before.name} maxed ${p.name}`,
        });
        const earned = await awardAchievement(supabase, characterId, "maxed_profession");
        if (earned) {
          events.push({
            character_id: characterId,
            user_id: before.user_id,
            kind: "achievement_earned",
            achievement_kind: "maxed_profession",
            achievement_tier: null,
            message: ACHIEVEMENT_MESSAGE.maxed_profession(before.name),
          });
        }
      }
    } else {
      await supabase.from("character_professions").insert({
        character_id: characterId,
        profession: p.name,
        skill,
        ...(recipes && recipes.length > 0 ? { recipes } : {}),
      });
      updatedProfessions.push({ id: "", profession: p.name, skill });

      if (skill >= MAX_SKILL) {
        events.push({
          character_id: characterId,
          user_id: before.user_id,
          kind: "profession_maxed",
          message: `${before.name} maxed ${p.name}`,
        });
        const earned = await awardAchievement(supabase, characterId, "maxed_profession");
        if (earned) {
          events.push({
            character_id: characterId,
            user_id: before.user_id,
            kind: "achievement_earned",
            achievement_kind: "maxed_profession",
            achievement_tier: null,
            message: ACHIEVEMENT_MESSAGE.maxed_profession(before.name),
          });
        }
      }
    }
  }

  // Renaissance - every profession this character can have (2 primary +
  // all 3 secondary) maxed out at once.
  const maxedPrimaryCount = updatedProfessions.filter(
    (p) => PRIMARY_PROFESSIONS.includes(p.profession) && p.skill >= MAX_SKILL
  ).length;
  const maxedSecondaryCount = updatedProfessions.filter(
    (p) => SECONDARY_PROFESSIONS.includes(p.profession) && p.skill >= MAX_SKILL
  ).length;
  if (maxedPrimaryCount >= 2 && maxedSecondaryCount >= SECONDARY_PROFESSIONS.length) {
    const earned = await awardAchievement(supabase, characterId, "renaissance");
    if (earned) {
      events.push({
        character_id: characterId,
        user_id: before.user_id,
        kind: "achievement_earned",
        achievement_kind: "renaissance",
        achievement_tier: null,
        message: ACHIEVEMENT_MESSAGE.renaissance(before.name),
      });
    }
  }

  // Recipes known - summed across every profession the character has, not
  // just the one(s) touched this sync, since the badge reflects the whole
  // shared library. Queried fresh from the DB (rather than from
  // `updatedProfessions`, which only tracks skill in memory) so it reflects
  // whatever was just written above. Also splits out a Cooking-only count
  // for the "Master Chef" badge (2026-09-26) - same profession-derived
  // special case as the all-professions "recipes"/Artisan badge above, just
  // scoped to one profession, so both are computed from this single query.
  const { data: allProfessionRecipes } = await supabase
    .from("character_professions")
    .select("profession, recipes")
    .eq("character_id", characterId);
  const totalRecipes = (allProfessionRecipes ?? []).reduce(
    (n, p) => n + (Array.isArray(p.recipes) ? p.recipes.length : 0),
    0
  );
  if (totalRecipes > 0) {
    const tier = await awardTier(supabase, characterId, "recipes", totalRecipes);
    if (tier) {
      events.push({
        character_id: characterId,
        user_id: before.user_id,
        kind: "achievement_earned",
        achievement_kind: "recipes",
        achievement_tier: tier,
        message: tierMessage("recipes", before.name, tier),
      });
    }
  }
  const cookingRecipes = (allProfessionRecipes ?? []).reduce(
    (n, p) =>
      n +
      (p.profession?.toLowerCase() === "cooking" && Array.isArray(p.recipes)
        ? p.recipes.length
        : 0),
    0
  );
  if (cookingRecipes > 0) {
    const masterChefTier = await awardTier(supabase, characterId, "master_chef", cookingRecipes);
    if (masterChefTier) {
      events.push({
        character_id: characterId,
        user_id: before.user_id,
        kind: "achievement_earned",
        achievement_kind: "master_chef",
        achievement_tier: masterChefTier,
        message: tierMessage("master_chef", before.name, masterChefTier),
      });
    }
  }

  // Addicted (2026-09-27) - total time played, converted from the addon's
  // raw seconds to whole hours (TIER_DEFS.addicted's thresholds are in
  // hours - much more readable than a seconds count). Same "computed
  // outside character_statistics" special case as recipes/master_chef
  // above, just sourced from parsed.basic instead of character_professions.
  // Skipped entirely (not even a 0-hour award attempt) until the addon's
  // async time-played fetch has actually returned something.
  if (typeof parsed.basic?.timePlayedSeconds === "number" && parsed.basic.timePlayedSeconds > 0) {
    const hoursPlayed = Math.floor(parsed.basic.timePlayedSeconds / 3600);
    const addictedTier = await awardTier(supabase, characterId, "addicted", hoursPlayed);
    if (addictedTier) {
      events.push({
        character_id: characterId,
        user_id: before.user_id,
        kind: "achievement_earned",
        achievement_kind: "addicted",
        achievement_tier: addictedTier,
        message: tierMessage("addicted", before.name, addictedTier),
      });
    }
  }

  // 4. Equipped gear - upsert whatever's filled, and clear out any tracked
  //    slot that's no longer present in the export (i.e. you unequipped it).
  //    Also compares against what was in each slot before, so equipping a
  //    new Epic or Legendary item (whichever quality - the two are
  //    combined into a single "notable gear" event, not split) can be
  //    logged to the activity feed.
  const { data: previousGear } = await supabase
    .from("equipped_gear")
    .select("slot, item_link, item_quality")
    .eq("character_id", characterId);
  const previousBySlot = new Map(
    ((previousGear ?? []) as { slot: string; item_link: string; item_quality: string | null }[]).map(
      (g) => [g.slot, g]
    )
  );

  const gearRows: {
    character_id: string;
    slot: string;
    item_name: string;
    item_link: string;
    item_id: number | null;
    item_quality: string | null;
    item_icon: string | null;
    tooltip: string[];
    updated_at: string;
  }[] = [];
  const emptySlots: string[] = [];
  let equippedNewLegendary = false;
  // Whether the addon reported ANY gear at all this export. GetInventoryItemLink
  // can come back nil for every slot if the export was captured before the
  // client had finished loading inventory data from the server (most likely
  // right at login, especially on a laggy connection) - collectGear() then
  // sends back an empty {}, indistinguishable from "you unequipped
  // everything" unless we check for it here. Actually unequipping every
  // single slot at once essentially never happens, while a bad/early read
  // is a real and observed failure mode, so an entirely empty report is
  // treated as "gear wasn't captured this sync" and leaves whatever was
  // already on file alone, rather than wiping it.
  const gearReported = !!parsed.gear && Object.keys(parsed.gear).length > 0;
  for (const [addonSlot, siteSlot] of Object.entries(GEAR_SLOT_MAP)) {
    const item = parsed.gear?.[addonSlot];
    if (!item) {
      if (gearReported) emptySlots.push(siteSlot);
      continue;
    }
    gearRows.push({
      character_id: characterId,
      slot: siteSlot,
      item_name: item.name,
      item_link: item.link,
      item_id: item.id ?? null,
      item_quality: item.color ?? null,
      item_icon: iconUrlForFileId(item.icon),
      tooltip: item.tooltip ?? [],
      updated_at: new Date().toISOString(),
    });

    const quality = item.color?.toLowerCase();
    const prev = previousBySlot.get(siteSlot);
    const isNewItem = prev?.item_link !== item.link;
    if (quality && NOTABLE_GEAR_COLORS.has(quality) && isNewItem) {
      events.push({
        character_id: characterId,
        user_id: before.user_id,
        kind: "epic_gear",
        message: `${before.name} equipped ${item.name}`,
      });
      if (quality === LEGENDARY_COLOR) equippedNewLegendary = true;
    }
  }

  // The Epic-gear TIER badge is no longer tracked here as a running count -
  // it's sourced from the Statistics pane's own "Epic items acquired" stat
  // in the Statistics-based badges section further down, which is
  // authoritative and already accounts for Epics equipped before this
  // feature existed (a manual counter starting from zero never could).

  // Legendary is its own one-off badge, separate from the Epic tier.
  if (equippedNewLegendary) {
    const earned = await awardAchievement(supabase, characterId, "legendary_item");
    if (earned) {
      events.push({
        character_id: characterId,
        user_id: before.user_id,
        kind: "achievement_earned",
        achievement_kind: "legendary_item",
        achievement_tier: null,
        message: ACHIEVEMENT_MESSAGE.legendary_item(before.name),
      });
    }
  }

  if (gearRows.length > 0) {
    // Keep the items table in sync with what's actually equipped. A live
    // scanned tooltip (present on every gear export from addon 1.6.0+) is
    // the only trustworthy source for an item's real quality/stats - WoW
    // Forever reuses classic item IDs but can rebalance them, and Blizzard's
    // classic API has no idea when that's happened (confirmed 2026-09-24 on
    // Runed Copper Belt: Blizzard says Common/86 Armor/no stats, the live
    // game says Uncommon/91 Armor/+3 Str/+2 Sta). So applyLiveObservation
    // always wins when there's a tooltip to read; ensureItemsExist (an
    // unverified Blizzard-baseline placeholder) only covers the rare case
    // where an item ID came through with no tooltip at all.
    const idsNeedingBaseline: number[] = [];
    const fallbacks = new Map<number, { name?: string; icon?: number | null }>();
    for (const addonSlot of Object.keys(GEAR_SLOT_MAP)) {
      const item = parsed.gear?.[addonSlot];
      if (item?.id == null) continue;
      if (item.tooltip && item.tooltip.length > 0) {
        try {
          await applyLiveObservation(supabase, item.id, {
            name: item.name,
            color: item.color ?? null,
            icon: item.icon ?? null,
            tooltip: item.tooltip,
          });
        } catch (e) {
          // Never let an item-database hiccup block the actual gear sync -
          // the equipped_gear upsert below is what matters for the
          // character page; items can catch up next sync.
          console.error(`applyLiveObservation failed for item ${item.id}:`, e);
        }
      } else {
        idsNeedingBaseline.push(item.id);
        fallbacks.set(item.id, { name: item.name, icon: item.icon ?? null });
      }
    }
    if (idsNeedingBaseline.length > 0) {
      try {
        await ensureItemsExist(supabase, idsNeedingBaseline, fallbacks);
      } catch (e) {
        console.error("ensureItemsExist failed during gear sync:", e);
      }
    }

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

  // 4b. Bag/bank contents - never written to any per-character table (no
  //     bag-viewer feature exists), purely fed through the item database
  //     pipeline so items get real data as soon as ANYONE's seen carrying
  //     them, not only once someone's actually worn them. Same
  //     "live tooltip always wins" rule as gear.
  for (const item of parsed.bagItems ?? []) {
    if (item.id == null) continue;
    try {
      if (item.tooltip && item.tooltip.length > 0) {
        await applyLiveObservation(supabase, item.id, {
          name: item.name,
          color: item.color ?? null,
          icon: item.icon ?? null,
          tooltip: item.tooltip,
        });
      } else {
        await ensureItemsExist(
          supabase,
          [item.id],
          new Map([[item.id, { name: item.name, icon: item.icon ?? null }]])
        );
      }
    } catch (e) {
      // Never let one bad bag item block the rest of the sync.
      console.error(`bag item sync failed for item ${item.id}:`, e);
    }
  }

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

  // 6. Statistics pane data - whatever the addon reports this sync fully
  //    replaces what's on file for those stat IDs, one upsert per exported
  //    stat, keyed on (character_id, stat_id).
  if (parsed.statistics && parsed.statistics.length > 0) {
    const statisticRows = parsed.statistics.map((s) => ({
      character_id: characterId,
      user_id: before.user_id,
      stat_id: s.id,
      category: s.category,
      name: s.name,
      value: s.value,
      updated_at: new Date().toISOString(),
    }));
    const { error } = await supabase
      .from("character_statistics")
      .upsert(statisticRows, { onConflict: "character_id,stat_id" });
    if (error) throw new Error(error.message);

    // Statistics-based badges (2026-09-25 rework, expanded 2026-09-25) - the
    // tiered achievements that used to be sourced from ad-hoc fields this
    // site tracked itself (a live gold balance, a hand-rolled equipped-Epic
    // counter) are now sourced from the game's own Statistics pane data
    // instead, plus a growing set of combined-stat badges (Well Supplied,
    // Wayfarer, Social Butterfly) that add several related raw stats into
    // one meaningful counter. TIER_COUNTERS in achievements.ts is the one
    // place that says which raw stat(s) feed which badge - shared with the
    // leaderboards page, so the two can never disagree about what a badge
    // actually measures. "recipes" is the one exception (computed from
    // character_professions above, not from Statistics), so it's skipped
    // here and awarded separately.
    for (const kind of TIERED_ACHIEVEMENT_KINDS) {
      if (kind === "recipes") continue;
      const value = computeCounter(kind, parsed.statistics);
      if (value <= 0) continue;
      const tier = await awardTier(supabase, characterId, kind, value);
      if (tier) {
        events.push({
          character_id: characterId,
          user_id: before.user_id,
          kind: "achievement_earned",
          achievement_kind: kind,
          achievement_tier: tier,
          message: tierMessage(kind, before.name, tier),
        });
      }
    }

    // One-off "personality badges" - a single threshold on one specific
    // Social-pane stat (separate from the combined "social" counter above,
    // which feeds Social Butterfly). Same silent-skip-if-never-recorded
    // behavior as everything else here.
    for (const badge of PERSONALITY_BADGES) {
      const row = parsed.statistics.find(
        (s) => s.category === badge.category && s.name === badge.name
      );
      if (!row) continue;
      const n = Number(row.value.replace(/,/g, ""));
      if (!Number.isFinite(n) || n < badge.threshold) continue;
      const earned = await awardAchievement(supabase, characterId, badge.kind);
      if (earned) {
        events.push({
          character_id: characterId,
          user_id: before.user_id,
          kind: "achievement_earned",
          achievement_kind: badge.kind,
          achievement_tier: null,
          message: ACHIEVEMENT_MESSAGE[badge.kind](before.name),
        });
      }
    }
  }

  // Legacy Challenges - the real Blizzard Achievements pane (see the
  // ParsedExport.legacyAchievements comment above). One upsert row per
  // achievement, keyed on (character_id, achievement_id), so a sync just
  // overwrites each achievement's current completed/criteria state in
  // place - there's no tier/points system here to award separately, this
  // is display-only data straight from the game's own pane.
  if (parsed.legacyAchievements && parsed.legacyAchievements.length > 0) {
    const legacyRows = parsed.legacyAchievements.map((a) => ({
      character_id: characterId,
      user_id: before.user_id,
      achievement_id: a.id,
      category: a.category,
      name: a.name,
      description: a.description ?? null,
      completed: a.completed,
      criteria: a.criteria && a.criteria.length > 0 ? a.criteria : null,
      icon: a.icon ?? null,
      updated_at: new Date().toISOString(),
    }));
    const { error } = await supabase
      .from("character_legacy_achievements")
      .upsert(legacyRows, { onConflict: "character_id,achievement_id" });
    if (error) throw new Error(error.message);
  }

  // Account-wide achievements - re-checked on every sync since any of the
  // updates above (level, gold, professions) could be what tips the
  // account over a threshold. Reads the account's current state fresh
  // rather than trying to track it incrementally, so it's safe even if a
  // sync only ever touches one character at a time. These have no single
  // character to attach to, so they post to the feed with a null
  // character_id (same as the Legacy-point event on the Dashboard).
  try {
    const accountMessages = await checkAccountAchievements(supabase, before.user_id);
    for (const message of accountMessages) {
      events.push({
        character_id: null,
        user_id: before.user_id,
        kind: "achievement_earned",
        message,
      });
    }
  } catch {
    // ignored on purpose - never blocks the sync itself
  }

  // Best-effort - a failure to log an activity event should never break
  // the sync itself, so this is never allowed to throw.
  if (events.length > 0) {
    try {
      await supabase.from("activity_events").insert(events);
    } catch {
      // ignored on purpose
    }
  }

  return {
    gearChanges: gearRows.map((r) => `${r.slot}: ${r.item_name}`),
    talentApplied,
    talentUnknown,
  };
}