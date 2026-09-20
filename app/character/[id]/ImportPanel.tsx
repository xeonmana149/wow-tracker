"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../../lib/supabase";

type Profession = { id: string; profession: string; skill: number };

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

type ParsedTraitNode = {
  entryID?: number;
  name?: string;
  tree?: string;
  rank: number;
  maxRank?: number;
};

type ParsedExport = {
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
  gear?: Record<string, { link: string; name: string; tooltip?: string[] }>;
  traits?: {
    experimental?: boolean;
    error?: string;
    configs?: { configID: number; nodes: ParsedTraitNode[] }[];
  };
};

// Maps a site stat key to how to pull the matching number out of the addon
// export. Only stats the addon actually reads are listed here - anything
// not covered here (weapon damage range, hit%, Defense) is left alone so an
// import never overwrites what you've typed in by hand for those.
const STAT_MAP: Record<string, (d: ParsedExport) => number | null | undefined> = {
  max_health: (d) => d.stats?.maxHealth,
  max_mana: (d) => d.stats?.maxMana,
  // Move speed is the character's speed *at the moment you exported*, so a
  // reading of 0 almost always just means you were standing still - skip it
  // rather than zeroing out a real value.
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

export default function ImportPanel({
  characterId,
  ownerId,
  professions,
  activeSpec,
}: {
  characterId: string;
  ownerId: string | null;
  professions: Profession[];
  activeSpec: number;
}) {
  const router = useRouter();
  const [isOwner, setIsOwner] = useState(false);
  const [open, setOpen] = useState(false);
  const [text, setText] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<ParsedExport | null>(null);
  const [gearChanges, setGearChanges] = useState<string[]>([]);
  const [talentResult, setTalentResult] = useState<{ applied: string[]; unknown: string[] }>({
    applied: [],
    unknown: [],
  });

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setIsOwner(!!ownerId && data.user?.id === ownerId);
    });
  }, [ownerId]);

  if (!isOwner) return null;

  async function handleImport() {
    setMessage("");
    let parsed: ParsedExport;
    try {
      parsed = JSON.parse(text);
    } catch {
      setMessage("That doesn't look like valid JSON. Copy the whole box from /wft export.");
      return;
    }

    setBusy(true);

    // 1. Character-level fields.
    const charUpdate: Record<string, number | string> = {};
    if (typeof parsed.basic?.level === "number") charUpdate.level = parsed.basic.level;
    if (typeof parsed.basic?.money === "number") charUpdate.gold = parsed.basic.money;
    if (parsed.basic?.guild) charUpdate.guild = parsed.basic.guild;

    if (Object.keys(charUpdate).length > 0) {
      const { error } = await supabase
        .from("characters")
        .update(charUpdate)
        .eq("id", characterId);
      if (error) {
        setMessage(error.message);
        setBusy(false);
        return;
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
      if (error) {
        setMessage(error.message);
        setBusy(false);
        return;
      }
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

    // 4. Equipped gear - straight overwrite of whatever's in each slot.
    const gearRows: {
      character_id: string;
      slot: string;
      item_name: string;
      item_link: string;
      tooltip: string[];
      updated_at: string;
    }[] = [];
    for (const [addonSlot, siteSlot] of Object.entries(GEAR_SLOT_MAP)) {
      const item = parsed.gear?.[addonSlot];
      if (!item) continue;
      gearRows.push({
        character_id: characterId,
        slot: siteSlot,
        item_name: item.name,
        item_link: item.link,
        tooltip: item.tooltip ?? [],
        updated_at: new Date().toISOString(),
      });
    }

    if (gearRows.length > 0) {
      const { error } = await supabase
        .from("equipped_gear")
        .upsert(gearRows, { onConflict: "character_id,slot" });
      if (error) {
        setMessage(error.message);
        setBusy(false);
        return;
      }
    }

    // 5. Talents - only nodes the addon already knows the name and tree for
    //    get written into the planner. Unmapped ones stay reference-only so
    //    an unidentified node can never silently overwrite a real talent.
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

    setResult(parsed);
    setGearChanges(gearRows.map((r) => `${r.slot}: ${r.item_name}`));
    setTalentResult({ applied: talentApplied, unknown: talentUnknown });
    setMessage(
      "Imported. Level, gold, guild, stats, professions, gear and recognized talents are updated."
    );
    setBusy(false);
    router.refresh();
  }

  return (
    <section className="mt-4 max-w-2xl rounded bg-neutral-800 p-4">
      <div className="flex items-center justify-between">
        <h2 className="font-bold">Import from Addon</h2>
        <button
          onClick={() => setOpen(!open)}
          className="rounded bg-blue-600 px-3 py-1 text-sm text-white"
        >
          {open ? "Hide" : "Import"}
        </button>
      </div>

      {open && (
        <>
          <p className="mt-2 text-sm text-gray-400">
            In game, run <code>/wft export</code>, copy the whole box (Ctrl+A, Ctrl+C), then
            paste it here.
          </p>

          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            rows={6}
            placeholder="Paste the JSON from /wft export here"
            className="mt-3 w-full rounded bg-white p-2 font-mono text-xs text-black"
          />

          <div className="mt-3 flex gap-2">
            <button
              onClick={handleImport}
              disabled={busy || !text.trim()}
              className="rounded bg-blue-600 px-4 py-2 text-white disabled:opacity-50"
            >
              {busy ? "Importing..." : "Import"}
            </button>
          </div>

          {message && <p className="mt-3 text-sm text-amber-300">{message}</p>}

          {result && (
            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              {gearChanges.length > 0 && (
                <div>
                  <h3 className="text-sm font-bold text-amber-400">Equipped gear imported</h3>
                  <ul className="mt-1 text-sm text-gray-300">
                    {gearChanges.map((line, i) => (
                      <li key={i}>{line}</li>
                    ))}
                  </ul>
                </div>
              )}

              {result.traits && (
                <div>
                  <h3 className="text-sm font-bold text-amber-400">Talents</h3>
                  {result.traits.error && (
                    <p className="mt-1 text-sm text-gray-400">{result.traits.error}</p>
                  )}
                  {talentResult.applied.length > 0 && (
                    <>
                      <p className="mt-1 text-xs text-gray-500">Applied to the Talent Planner:</p>
                      <ul className="text-sm text-gray-300">
                        {talentResult.applied.map((line, i) => (
                          <li key={i}>{line}</li>
                        ))}
                      </ul>
                    </>
                  )}
                  {talentResult.unknown.length > 0 && (
                    <>
                      <p className="mt-2 text-xs text-gray-500">
                        Not yet recognized (tell me what these are so they can be added):
                      </p>
                      <ul className="text-sm text-gray-400">
                        {talentResult.unknown.map((line, i) => (
                          <li key={i}>{line}</li>
                        ))}
                      </ul>
                    </>
                  )}
                </div>
              )}
            </div>
          )}
        </>
      )}
    </section>
  );
}
