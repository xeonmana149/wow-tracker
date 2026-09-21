"use client";

import { useState, FormEvent } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../../../lib/supabase";
import { copperToParts } from "../../../../lib/money";
import { awardAchievement, ACHIEVEMENT_MESSAGE } from "../../../../lib/achievements";
import { CHARACTER_TYPES, ROLES, RULESETS, RACE_FACTION, SPECS } from "../../../../lib/options";

type Character = {
  id: string;
  name: string;
  race: string;
  class: string;
  level: number;
  guild: string | null;
  character_type: string;
  ruleset: string | null;
  main_spec: string | null;
  main_role: string;
  off_spec: string | null;
  off_role: string | null;
  pvp_rank: number;
  honor_points: number;
  money_copper: number;
  legacy_points_spent: number;
};

// Older characters may have a spec that isn't in the list. Blank it so it gets re-picked.
function validSpec(cls: string, spec: string | null) {
  return spec && (SPECS[cls] ?? []).some((s) => s.name === spec) ? spec : "";
}

export default function EditForm({ character }: { character: Character }) {
  const router = useRouter();

  // Name isn't editable at all here - it can't actually be changed in-game,
  // and even if you typed a different value in here, sync matches
  // characters by this exact name, so changing it would just make the next
  // sync fail to find this row and create a duplicate instead of updating
  // it.
  const displayName = character.name;

  const [mainSpec, setMainSpec] = useState(validSpec(character.class, character.main_spec));
  const [mainRole, setMainRole] = useState(character.main_role);
  const [offSpec, setOffSpec] = useState(validSpec(character.class, character.off_spec));
  const [offRole, setOffRole] = useState(character.off_role ?? "");
  const [ruleset, setRuleset] = useState(character.ruleset ?? "");
  const [characterType, setCharacterType] = useState(character.character_type);
  const [pvpRank, setPvpRank] = useState(character.pvp_rank);
  const [legacyPointsSpent, setLegacyPointsSpent] = useState(character.legacy_points_spent);
  const [message, setMessage] = useState("");

  // Name, race, class, level, guild, gold and honor aren't edited here at
  // all - the addon overwrites (or, for name/race/class, simply always
  // matches) these on every sync, so a manual edit here would either do
  // nothing useful or get silently reverted. They're shown read-only below
  // for context instead.
  const currentMoney = copperToParts(character.money_copper);

  const specs = SPECS[character.class] ?? [];

  function handleMainSpecChange(name: string) {
    setMainSpec(name);
    const found = specs.find((s) => s.name === name);
    if (found) setMainRole(found.role);
    if (offSpec === name) {
      setOffSpec("");
      setOffRole("");
    }
  }

  function handleOffSpecChange(name: string) {
    setOffSpec(name);
    const found = specs.find((s) => s.name === name);
    setOffRole(found ? found.role : "");
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setMessage("Saving...");

    const { error } = await supabase
      .from("characters")
      .update({
        character_type: characterType,
        ruleset,
        main_spec: mainSpec,
        main_role: mainRole,
        off_spec: offSpec || null,
        off_role: offSpec ? offRole : null,
        pvp_rank: pvpRank,
        legacy_points_spent: legacyPointsSpent,
      })
      .eq("id", character.id);

    if (error) {
      setMessage(`Something went wrong: ${error.message}`);
      return;
    }

    // Activity feed + achievements - best-effort, never blocks the save
    // itself since the character update above already succeeded.
    try {
      const { data: userData } = await supabase.auth.getUser();
      const uid = userData.user?.id;
      if (uid) {
        const newEvents: { character_id: string; user_id: string; kind: string; message: string }[] =
          [];

        // Only fires on a genuine rank increase, never a decrease or an
        // unchanged save.
        if (pvpRank > character.pvp_rank) {
          newEvents.push({
            character_id: character.id,
            user_id: uid,
            kind: "pvp_rank_up",
            message: `${displayName} reached PvP rank ${pvpRank}`,
          });
        }

        const TOP_PVP_RANK = 14;
        if (pvpRank >= TOP_PVP_RANK) {
          const earned = await awardAchievement(supabase, character.id, "top_pvp_rank");
          if (earned) {
            newEvents.push({
              character_id: character.id,
              user_id: uid,
              kind: "achievement_earned",
              message: ACHIEVEMENT_MESSAGE.top_pvp_rank(displayName),
            });
          }
        }

        if (newEvents.length > 0) {
          await supabase.from("activity_events").insert(newEvents);
        }
      }
    } catch {
      // ignored on purpose
    }

    router.push(`/character/${character.id}`);
    router.refresh();
  }

  return (
    <form onSubmit={handleSubmit} className="mt-6 flex max-w-3xl flex-col gap-6">
      <div className="rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
        <h2 className="text-xs font-semibold uppercase tracking-wide text-gray-400">
          From your last sync
        </h2>
        <p className="mt-1 text-xs text-gray-500">
          Name, race, class, level, guild, gold and honor come from the addon and update
          automatically every time you log out or /reload - editing them here would just get
          overwritten (or, for name, isn&apos;t possible to change in the first place), so
          they&apos;re not editable on this page.
        </p>
        <div className="mt-3 flex flex-wrap gap-4 text-sm">
          <div>
            <div className="text-gray-500">Name</div>
            <div className="font-semibold text-white">{displayName}</div>
          </div>
          <div>
            <div className="text-gray-500">Race</div>
            <div className="font-semibold text-white">
              {character.race}
              {RACE_FACTION[character.race] && (
                <span className="ml-1 font-normal text-gray-400">
                  ({RACE_FACTION[character.race]})
                </span>
              )}
            </div>
          </div>
          <div>
            <div className="text-gray-500">Class</div>
            <div className="font-semibold text-white">{character.class}</div>
          </div>
          <div>
            <div className="text-gray-500">Level</div>
            <div className="font-semibold text-white">{character.level}</div>
          </div>
          <div>
            <div className="text-gray-500">Guild</div>
            <div className="font-semibold text-white">{character.guild || "None"}</div>
          </div>
          <div>
            <div className="text-gray-500">Gold</div>
            <div className="font-semibold text-white">
              {currentMoney.gold}g {currentMoney.silver}s {currentMoney.copper}c
            </div>
          </div>
          <div>
            <div className="text-gray-500">Honor points</div>
            <div className="font-semibold text-white">{character.honor_points}</div>
          </div>
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <label className="flex flex-col gap-1">
          Character type
          <select
            value={characterType}
            onChange={(e) => setCharacterType(e.target.value)}
            className="rounded bg-white p-2 text-black"
          >
            {CHARACTER_TYPES.map((t) => (
              <option key={t}>{t}</option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1">
          Ruleset
          <select
            value={ruleset}
            onChange={(e) => setRuleset(e.target.value)}
            className="rounded bg-white p-2 text-black"
            required
          >
            <option value="">Choose a ruleset</option>
            {RULESETS.map((r) => (
              <option key={r}>{r}</option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1">
          Main spec
          <select
            value={mainSpec}
            onChange={(e) => handleMainSpecChange(e.target.value)}
            className="rounded bg-white p-2 text-black"
            required
          >
            <option value="">Choose a spec</option>
            {specs.map((s) => (
              <option key={s.name}>{s.name}</option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1">
          Main spec role
          <select
            value={mainRole}
            onChange={(e) => setMainRole(e.target.value)}
            className="rounded bg-white p-2 text-black"
            required
          >
            <option value="">Choose a role</option>
            {ROLES.map((r) => (
              <option key={r}>{r}</option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1">
          Off spec (optional)
          <select
            value={offSpec}
            onChange={(e) => handleOffSpecChange(e.target.value)}
            className="rounded bg-white p-2 text-black"
          >
            <option value="">None</option>
            {specs
              .filter((s) => s.name !== mainSpec)
              .map((s) => (
                <option key={s.name}>{s.name}</option>
              ))}
          </select>
        </label>

        {offSpec && (
          <label className="flex flex-col gap-1">
            Off spec role
            <select
              value={offRole}
              onChange={(e) => setOffRole(e.target.value)}
              className="rounded bg-white p-2 text-black"
              required
            >
              {ROLES.map((r) => (
                <option key={r}>{r}</option>
              ))}
            </select>
          </label>
        )}

        <label className="flex flex-col gap-1">
          PvP rank (0 to 14)
          <input
            type="number"
            min={0}
            max={14}
            value={pvpRank}
            onChange={(e) => setPvpRank(Number(e.target.value))}
            className="rounded bg-white p-2 text-black"
          />
        </label>

        <label className="flex flex-col gap-1">
          Legacy points spent
          <input
            type="number"
            min={0}
            value={legacyPointsSpent}
            onChange={(e) => setLegacyPointsSpent(Number(e.target.value))}
            className="rounded bg-white p-2 text-black"
          />
        </label>
      </div>

      <div>
        <button type="submit" className="rounded bg-blue-600 px-4 py-2 text-white">
          Save Changes
        </button>
      </div>

      {message && <p className="text-red-400">{message}</p>}
    </form>
  );
}