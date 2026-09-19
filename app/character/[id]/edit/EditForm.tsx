"use client";

import { useState, FormEvent } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../../../lib/supabase";
import {
  RACES,
  CLASSES,
  CHARACTER_TYPES,
  ROLES,
  RULESETS,
  RACE_FACTION,
  SPECS,
} from "../../../../lib/options";

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
  gold: number;
  legacy_points_spent: number;
};

// Older characters may have a spec that isn't in the list. Blank it so it gets re-picked.
function validSpec(cls: string, spec: string | null) {
  return spec && (SPECS[cls] ?? []).some((s) => s.name === spec) ? spec : "";
}

export default function EditForm({ character }: { character: Character }) {
  const router = useRouter();

  // The full name is stored as "First Last", so split it for the two boxes
  const [startFirst, ...startRest] = character.name.split(" ");

  const [firstName, setFirstName] = useState(startFirst);
  const [lastName, setLastName] = useState(startRest.join(" "));
  const [race, setRace] = useState(RACES.includes(character.race) ? character.race : "");
  const [charClass, setCharClass] = useState(
    CLASSES.includes(character.class) ? character.class : ""
  );
  const [mainSpec, setMainSpec] = useState(validSpec(character.class, character.main_spec));
  const [mainRole, setMainRole] = useState(character.main_role);
  const [offSpec, setOffSpec] = useState(validSpec(character.class, character.off_spec));
  const [offRole, setOffRole] = useState(character.off_role ?? "");
  const [ruleset, setRuleset] = useState(character.ruleset ?? "");
  const [level, setLevel] = useState(character.level);
  const [guild, setGuild] = useState(character.guild ?? "");
  const [characterType, setCharacterType] = useState(character.character_type);
  const [pvpRank, setPvpRank] = useState(character.pvp_rank);
  const [honorPoints, setHonorPoints] = useState(character.honor_points);
  const [gold, setGold] = useState(character.gold);
  const [legacyPointsSpent, setLegacyPointsSpent] = useState(character.legacy_points_spent);
  const [message, setMessage] = useState("");

  const specs = SPECS[charClass] ?? [];

  function handleClassChange(newClass: string) {
    setCharClass(newClass);
    setMainSpec("");
    setMainRole("");
    setOffSpec("");
    setOffRole("");
  }

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
        name: `${firstName.trim()} ${lastName.trim()}`,
        race,
        class: charClass,
        level,
        guild: guild.trim() || null,
        character_type: characterType,
        ruleset,
        main_spec: mainSpec,
        main_role: mainRole,
        off_spec: offSpec || null,
        off_role: offSpec ? offRole : null,
        pvp_rank: pvpRank,
        honor_points: honorPoints,
        gold,
        legacy_points_spent: legacyPointsSpent,
      })
      .eq("id", character.id);

    if (error) {
      setMessage(`Something went wrong: ${error.message}`);
    } else {
      router.push(`/character/${character.id}`);
      router.refresh();
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mt-6 flex max-w-sm flex-col gap-4">
      <label className="flex flex-col gap-1">
        First name
        <input
          value={firstName}
          onChange={(e) => setFirstName(e.target.value)}
          pattern="\S+"
          title="One word, no spaces"
          className="rounded bg-white p-2 text-black"
          required
        />
      </label>

      <label className="flex flex-col gap-1">
        Last name
        <input
          value={lastName}
          onChange={(e) => setLastName(e.target.value)}
          pattern="\S+"
          title="One word, no spaces"
          className="rounded bg-white p-2 text-black"
          required
        />
      </label>

      <label className="flex flex-col gap-1">
        Race
        <select
          value={race}
          onChange={(e) => setRace(e.target.value)}
          className="rounded bg-white p-2 text-black"
          required
        >
          <option value="">Choose a race</option>
          {RACES.map((r) => (
            <option key={r}>{r}</option>
          ))}
        </select>
        {race && (
          <span className="text-sm text-gray-400">Faction: {RACE_FACTION[race]}</span>
        )}
      </label>

      <label className="flex flex-col gap-1">
        Class
        <select
          value={charClass}
          onChange={(e) => handleClassChange(e.target.value)}
          className="rounded bg-white p-2 text-black"
          required
        >
          <option value="">Choose a class</option>
          {CLASSES.map((c) => (
            <option key={c}>{c}</option>
          ))}
        </select>
      </label>

      <label className="flex flex-col gap-1">
        Main spec
        <select
          value={mainSpec}
          onChange={(e) => handleMainSpecChange(e.target.value)}
          disabled={!charClass}
          className="rounded bg-white p-2 text-black disabled:opacity-50"
          required
        >
          <option value="">
            {charClass ? "Choose a spec" : "Choose a class first"}
          </option>
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
          disabled={!charClass}
          className="rounded bg-white p-2 text-black disabled:opacity-50"
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
        Level
        <input
          type="number"
          min={1}
          max={60}
          value={level}
          onChange={(e) => setLevel(Number(e.target.value))}
          className="rounded bg-white p-2 text-black"
        />
      </label>

      <label className="flex flex-col gap-1">
        Guild (optional)
        <input
          value={guild}
          onChange={(e) => setGuild(e.target.value)}
          className="rounded bg-white p-2 text-black"
        />
      </label>

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
        Honor points
        <input
          type="number"
          min={0}
          value={honorPoints}
          onChange={(e) => setHonorPoints(Number(e.target.value))}
          className="rounded bg-white p-2 text-black"
        />
      </label>

      <label className="flex flex-col gap-1">
        Gold
        <input
          type="number"
          min={0}
          value={gold}
          onChange={(e) => setGold(Number(e.target.value))}
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

      <button type="submit" className="rounded bg-blue-600 px-4 py-2 text-white">
        Save Changes
      </button>

      {message && <p className="text-red-400">{message}</p>}
    </form>
  );
}