"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";

const RULESET_OPTIONS = ["PVP", "PVE", "RPPVE", "HARDCORE"];

type Props = {
  characterId: string;
  ownerId: string;
  needsSetup: boolean;
  currentMainSpec: string | null;
  currentRuleset: string | null;
};

export default function NeedsSetupBanner({
  characterId,
  ownerId,
  needsSetup,
  currentMainSpec,
  currentRuleset,
}: Props) {
  const [isOwner, setIsOwner] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  const [mainSpec, setMainSpec] = useState(
    currentMainSpec && currentMainSpec !== "Unspecified" ? currentMainSpec : ""
  );
  const [ruleset, setRuleset] = useState(
    currentRuleset && RULESET_OPTIONS.includes(currentRuleset) ? currentRuleset : "PVE"
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
    const { error } = await supabase
      .from("characters")
      .update({
        main_spec: mainSpec.trim(),
        ruleset,
        needs_setup: false,
      })
      .eq("id", characterId);

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
          <input
            type="text"
            value={mainSpec}
            onChange={(e) => setMainSpec(e.target.value)}
            placeholder="e.g. Retribution"
            className="mt-1 w-full rounded bg-neutral-900 px-3 py-2 text-sm text-white"
          />
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