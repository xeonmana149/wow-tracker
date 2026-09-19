"use client";

import { useState, useEffect, FormEvent, ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import {
  RACES,
  FACTIONS,
  RACE_FACTION,
  RACE_CLASSES,
  SPECS,
  ROLES,
  RULESETS,
  CHARACTER_TYPES,
} from "../../lib/options";
import { RACE_ICONS, classIcon } from "../../lib/icons";
import GameIcon from "../GameIcon";

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-2">
      <div className="text-sm font-bold text-gray-300">{label}</div>
      {children}
    </div>
  );
}

// A row of buttons where one can be selected, optionally with a picture on each
function Choice({
  options,
  value,
  onChange,
  emptyText,
  allowClear = false,
  icon,
}: {
  options: string[];
  value: string;
  onChange: (v: string) => void;
  emptyText?: string;
  allowClear?: boolean;
  icon?: (option: string) => string | undefined;
}) {
  if (options.length === 0) {
    return <p className="text-sm text-gray-500">{emptyText}</p>;
  }

  return (
    <div className="flex flex-wrap gap-2">
      {options.map((o) => (
        <button
          key={o}
          type="button"
          onClick={() => onChange(allowClear && o === value ? "" : o)}
          className={`flex items-center gap-2 rounded px-3 py-2 text-sm ${
            o === value
              ? "bg-blue-600 text-white"
              : "bg-neutral-700 text-gray-200 hover:bg-neutral-600"
          }`}
        >
          {icon && <GameIcon name={icon(o)} label={o} size={26} />}
          {o}
        </button>
      ))}
    </div>
  );
}

export default function CreateForm({ specIcons }: { specIcons: Record<string, string> }) {
  const router = useRouter();
  const [loggedIn, setLoggedIn] = useState<boolean | null>(null);
  const [pvpFaction, setPvpFaction] = useState<string | null>(null);
  const [ruleset, setRuleset] = useState("");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [faction, setFaction] = useState("");
  const [race, setRace] = useState("");
  const [charClass, setCharClass] = useState("");
  const [mainSpec, setMainSpec] = useState("");
  const [mainRole, setMainRole] = useState("");
  const [offSpec, setOffSpec] = useState("");
  const [offRole, setOffRole] = useState("");
  const [level, setLevel] = useState(1);
  const [guild, setGuild] = useState("");
  const [characterType, setCharacterType] = useState("Main");
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    supabase.auth.getUser().then(async ({ data }) => {
      setLoggedIn(!!data.user);
      if (!data.user) return;

      // If you already have a PVP character, new PVP characters must match its faction
      const { data: mine } = await supabase
        .from("characters")
        .select("race")
        .eq("user_id", data.user.id)
        .eq("ruleset", "PVP");
      const first = (mine ?? [])[0];
      setPvpFaction(first ? RACE_FACTION[first.race] ?? null : null);
    });
  }, []);

  // What each step offers, based on the steps before it
  const lockedFaction = ruleset === "PVP" ? pvpFaction : null;
  const racesForFaction = RACES.filter((r) => RACE_FACTION[r] === faction);
  const classesForRace = RACE_CLASSES[race] ?? [];
  const specs = SPECS[charClass] ?? [];

  const firstOk = /^\S+$/.test(firstName.trim());
  const lastOk = /^\S+$/.test(lastName.trim());
  const levelOk = Number.isInteger(level) && level >= 1 && level <= 60;

  const missing: string[] = [];
  if (!ruleset) missing.push("Ruleset");
  if (!firstOk) missing.push("First name");
  if (!lastOk) missing.push("Last name");
  if (!faction) missing.push("Faction");
  if (!race) missing.push("Race");
  if (!charClass) missing.push("Class");
  if (!mainSpec) missing.push("Main spec");
  if (!mainRole) missing.push("Main spec role");
  if (!levelOk) missing.push("Level (1 to 60)");

  function clearClass() {
    setCharClass("");
    setMainSpec("");
    setMainRole("");
    setOffSpec("");
    setOffRole("");
  }

  function handleRulesetChange(r: string) {
    setRuleset(r);
    // A PVP ruleset with an existing PVP character fixes the faction
    if (r === "PVP" && pvpFaction && faction !== pvpFaction) {
      setFaction(pvpFaction);
      setRace("");
      clearClass();
    }
  }

  function handleFactionChange(f: string) {
    if (lockedFaction && f !== lockedFaction) return;
    if (f === faction) return;
    setFaction(f);
    setRace("");
    clearClass();
  }

  function handleRaceChange(r: string) {
    setRace(r);
    // Keep the class if the new race can also be that class
    if (!(RACE_CLASSES[r] ?? []).includes(charClass)) clearClass();
  }

  function handleClassChange(c: string) {
    if (c === charClass) return;
    setCharClass(c);
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
    if (missing.length > 0 || saving) return;

    setSaving(true);
    setMessage("");

    const { data, error } = await supabase
      .from("characters")
      .insert({
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
      })
      .select("id")
      .single();

    if (error || !data) {
      setMessage(`Something went wrong: ${error?.message ?? "no response"}`);
      setSaving(false);
    } else {
      router.push(`/character/${data.id}`);
    }
  }

  if (loggedIn === null) {
    return <main className="p-8">Loading...</main>;
  }

  if (!loggedIn) {
    return (
      <main className="p-8">
        <Link href="/" className="text-blue-400">← Back</Link>
        <h1 className="mt-4 text-3xl font-bold">Create Character</h1>
        <p className="mt-4">
          You need to{" "}
          <Link href="/login" className="text-blue-400">log in</Link>{" "}
          before you can create a character.
        </p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-5xl p-8">
      <Link href="/" className="text-blue-400">← Back</Link>
      <h1 className="mt-4 text-3xl font-bold">Create Character</h1>

      <form onSubmit={handleSubmit} className="mt-6 grid gap-6 md:grid-cols-5">
        {/* Left: everything the game requires, in order */}
        <section className="rounded bg-neutral-800 p-5 md:col-span-3">
          <h2 className="text-lg font-bold">Required</h2>
          <p className="text-sm text-gray-400">
            Everything the game asks for when you make a character.
          </p>

          <div className="mt-5 flex flex-col gap-6">
            <Field label="1. Ruleset">
              <Choice options={RULESETS} value={ruleset} onChange={handleRulesetChange} />
              <p className="text-xs text-gray-500">
                All of your PVP characters have to be on the same faction.
              </p>
            </Field>

            <Field label="2. Name">
              <div className="grid grid-cols-2 gap-3">
                <input
                  placeholder="First name"
                  aria-label="First name"
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                  className="rounded bg-white p-2 text-black"
                />
                <input
                  placeholder="Last name"
                  aria-label="Last name"
                  value={lastName}
                  onChange={(e) => setLastName(e.target.value)}
                  className="rounded bg-white p-2 text-black"
                />
              </div>
              <p className="text-xs text-gray-500">One word each, no spaces.</p>
            </Field>

            <Field label="3. Faction">
              <div className="grid grid-cols-2 gap-3">
                {FACTIONS.map((f) => {
                  const blocked = !!lockedFaction && f !== lockedFaction;
                  return (
                    <button
                      key={f}
                      type="button"
                      disabled={blocked}
                      onClick={() => handleFactionChange(f)}
                      className={`rounded px-4 py-3 font-bold disabled:opacity-30 ${
                        faction === f
                          ? f === "Alliance"
                            ? "bg-blue-600 text-white"
                            : "bg-red-700 text-white"
                          : "bg-neutral-700 text-gray-300 hover:bg-neutral-600"
                      }`}
                    >
                      {f}
                    </button>
                  );
                })}
              </div>
              {lockedFaction && (
                <p className="text-xs text-yellow-500">
                  Your other PVP characters are {lockedFaction}, so a PVP character has to be{" "}
                  {lockedFaction} too.
                </p>
              )}
            </Field>

            <Field label="4. Race">
              <Choice
                options={racesForFaction}
                value={race}
                onChange={handleRaceChange}
                icon={(o) => RACE_ICONS[o]}
                emptyText="Choose a faction first"
              />
            </Field>

            <Field label="5. Class">
              <Choice
                options={classesForRace}
                value={charClass}
                onChange={handleClassChange}
                icon={classIcon}
                emptyText="Choose a race first"
              />
            </Field>

            <Field label="6. Main spec">
              <Choice
                options={specs.map((s) => s.name)}
                value={mainSpec}
                onChange={handleMainSpecChange}
                icon={(o) => specIcons[`${charClass}|${o}`]}
                emptyText="Choose a class first"
              />
            </Field>

            <Field label="7. Main spec role">
              <Choice options={ROLES} value={mainRole} onChange={setMainRole} />
              <p className="text-xs text-gray-500">
                Fills in when you pick a spec, and you can change it.
              </p>
            </Field>
          </div>
        </section>

        {/* Right: optional extras, then the summary and save button */}
        <div className="flex flex-col gap-6 md:col-span-2">
          <section className="rounded bg-neutral-800 p-5">
            <h2 className="text-lg font-bold">Optional</h2>
            <p className="text-sm text-gray-400">
              You can skip these and change them later.
            </p>

            <div className="mt-5 flex flex-col gap-6">
              <Field label="Off spec">
                <Choice
                  options={specs.filter((s) => s.name !== mainSpec).map((s) => s.name)}
                  value={offSpec}
                  onChange={handleOffSpecChange}
                  icon={(o) => specIcons[`${charClass}|${o}`]}
                  allowClear
                  emptyText="Choose a class first"
                />
                {offSpec && (
                  <p className="text-xs text-gray-500">Click it again to remove it.</p>
                )}
              </Field>

              {offSpec && (
                <Field label="Off spec role">
                  <Choice options={ROLES} value={offRole} onChange={setOffRole} />
                </Field>
              )}

              <div className="grid grid-cols-2 gap-3">
                <Field label="Level">
                  <input
                    type="number"
                    min={1}
                    max={60}
                    value={level}
                    onChange={(e) => setLevel(Number(e.target.value))}
                    className="rounded bg-white p-2 text-black"
                  />
                </Field>
                <Field label="Guild">
                  <input
                    value={guild}
                    onChange={(e) => setGuild(e.target.value)}
                    className="rounded bg-white p-2 text-black"
                  />
                </Field>
              </div>

              <Field label="Character type">
                <Choice
                  options={CHARACTER_TYPES}
                  value={characterType}
                  onChange={setCharacterType}
                />
              </Field>
            </div>
          </section>

          <section className="rounded bg-neutral-800 p-5">
            <div className="flex items-center gap-3">
              {charClass && <GameIcon name={classIcon(charClass)} label={charClass} size={44} round />}
              <h2 className="text-lg font-bold">
                {`${firstName} ${lastName}`.trim() || "New character"}
              </h2>
            </div>
            <p className="mt-1 text-sm text-gray-400">
              {[race, charClass].filter(Boolean).join(" ") ||
                "Race and class not chosen yet"}
            </p>
            <p className="text-sm text-gray-400">
              {[faction, ruleset].filter(Boolean).join(" · ")}
            </p>
            {mainSpec && (
              <p className="text-sm text-gray-400">
                {mainSpec}
                {mainRole && ` (${mainRole})`}
              </p>
            )}

            {missing.length > 0 && (
              <p className="mt-4 text-sm text-yellow-500">
                Still needed: {missing.join(", ")}
              </p>
            )}

            <button
              type="submit"
              disabled={missing.length > 0 || saving}
              className="mt-4 w-full rounded bg-blue-600 px-4 py-2 text-white disabled:cursor-not-allowed disabled:opacity-40"
            >
              {saving ? "Saving..." : "Save Character"}
            </button>

            {message && <p className="mt-3 text-sm text-red-400">{message}</p>}
          </section>
        </div>
      </form>
    </main>
  );
}