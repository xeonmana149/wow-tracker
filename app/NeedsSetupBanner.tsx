"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";
import { SPECS } from "../../../lib/options";

const RULESET_OPTIONS = ["PVP", "PVE", "RPPVE", "HARDCORE"];
const CHARACTER_TYPE_OPTIONS = ["Unspecified", "Main", "Alt", "Gatherer", "PvPer"];

type Props = {
  characterId: string;
  ownerId: string;
  needsSetup: boolean;
  currentMainSpec: string | null;
  currentRuleset: string | null;
  currentCharacterType: string | null;
  characterClass: string;
};

export default function NeedsSetupBanner({
  characterId,
  ownerId,
  needsSetup,
  currentMainSpec,
  currentRuleset,
  currentCharacterType,
  characterClass,
}: Props) {
  const [isOwner, setIsOwner] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  // The site's own class -> spec list (same one used everywhere else, so
  // whatever gets picked here matches the spec icon lookups on the
  // character card and page). Falls back to a free-text box only if the
  // class isn't one SPECS knows about.
  const classSpecs = SPECS[characterClass] ?? [];
  const [mainSpec, setMainSpec] = useState(() => {
    if (currentMainSpec && classSpecs.some((s) => s.name === currentMainSpec)) {
      return currentMainSpec;
    }
    return classSpecs[0]?.name ?? "";
  });
  const [ruleset, setRuleset] = useState(
    currentRuleset && RULESET_OPTIONS.includes(currentRuleset) ? currentRuleset : "PVE"
  );
  const [characterType, setCharacterType] = useState(
    currentCharacterType && CHARACTER_TYPE_OPTIONS.includes(currentCharacterType)
      ? currentCharacterType
      : "Unspecified"
  );
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setIsOwner(data.user?.id === ownerId);
    });
  }, [ownerId]);

  if (!needsSetup || dismissed || !isOwner) return null;

  async function save() {
    if (!mainSpec.trim()) {
      setMessage("Main spec can't be empty.");
      return;
    }
    setSaving(true);
    setMessage("");
    // Picking a spec from the dropdown also sets the matching role
    // (Tank/Healer/DPS), same default the rest of the site uses for that
    // spec - the addon has no way to set this at creation time, so it's
    // been sitting on the column's default (DPS) until now.
    const matchedRole = classSpecs.find((s) => s.name === mainSpec)?.role;
    const update: Record<string, string | boolean> = {
      main_spec: mainSpec.trim(),
      ruleset,
      character_type: characterType,
      needs_setup: false,
    };
    if (matchedRole) {
      update.main_role = matchedRole;
    }
    const { error } = await supabase.from("characters").update(update).eq("id", characterId);

    if (error) {
      setMessage(error.message);
      setSaving(false);
      return;
    }
    setSaving(false);
    setDismissed(true);
  }

  return (
    <section className="mb-4 rounded-lg border-2 border-amber-400 bg-amber-500/10 p-5 shadow-lg shadow-amber-900/30">
      <p className="flex items-center gap-2 text-lg font-bold text-amber-300">
        <span className="text-2xl">⚠</span> This character needs attention
      </p>
      <p className="mt-1 text-sm text-amber-100/80">
        It was auto-created from the game and is missing details the addon can&apos;t
        detect. Fill these in so it shows up correctly everywhere.
      </p>

      <div className="mt-4 flex flex-col gap-3 sm:flex-row">
        <div className="flex-1">
          <label className="block text-xs font-medium text-amber-200">Main spec</label>
          {classSpecs.length > 0 ? (
            <select
              value={mainSpec}
              onChange={(e) => setMainSpec(e.target.value)}
              className="mt-1 w-full rounded bg-neutral-900 px-3 py-2 text-sm text-white"
            >
              {classSpecs.map((s) => (
                <option key={s.name} value={s.name}>
                  {s.name} ({s.role})
                </option>
              ))}
            </select>
          ) : (
            <input
              type="text"
              value={mainSpec}
              onChange={(e) => setMainSpec(e.target.value)}
              placeholder="e.g. Retribution"
              className="mt-1 w-full rounded bg-neutral-900 px-3 py-2 text-sm text-white"
            />
          )}
        </div>

        <div className="flex-1">
          <label className="block text-xs font-medium text-amber-200">Ruleset</label>
          <select
            value={ruleset}
            onChange={(e) => setRuleset(e.target.value)}
            className="mt-1 w-full rounded bg-neutral-900 px-3 py-2 text-sm text-white"
          >
            {RULESET_OPTIONS.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>
        </div>

        <div className="flex-1">
          <label className="block text-xs font-medium text-amber-200">Character type</label>
          <select
            value={characterType}
            onChange={(e) => setCharacterType(e.target.value)}
            className="mt-1 w-full rounded bg-neutral-900 px-3 py-2 text-sm text-white"
          >
            {CHARACTER_TYPE_OPTIONS.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </div>
      </div>

      <button
        onClick={save}
        disabled={saving}
        className="mt-4 rounded bg-amber-500 px-5 py-2.5 text-sm font-bold text-neutral-950 hover:bg-amber-400 disabled:opacity-50"
      >
        {saving ? "Saving..." : "Save and dismiss"}
      </button>

      {message && <p className="mt-2 text-sm text-red-400">{message}</p>}
    </section>
  );
}
