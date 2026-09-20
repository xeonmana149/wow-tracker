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
    <section className="mt-4 max-w-2xl rounded border border-amber-500 bg-amber-950/40 p-4">
      <p className="font-semibold text-amber-300">⚠ Needs attention</p>
      <p className="mt-1 text-sm text-gray-300">
        This character was auto-created from the game and is missing a couple of details
        the addon can't detect. Fill these in and save.
      </p>

      <div className="mt-3 flex flex-col gap-3 sm:flex-row">
        <div className="flex-1">
          <label className="block text-xs text-gray-400">Main spec</label>
          <input
            type="text"
            value={mainSpec}
            onChange={(e) => setMainSpec(e.target.value)}
            placeholder="e.g. Retribution"
            className="mt-1 w-full rounded bg-neutral-900 px-3 py-2 text-sm text-white"
          />
        </div>

        <div className="flex-1">
          <label className="block text-xs text-gray-400">Ruleset</label>
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
        className="mt-3 rounded bg-amber-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
      >
        {saving ? "Saving..." : "Save and dismiss"}
      </button>

      {message && <p className="mt-2 text-sm text-red-400">{message}</p>}
    </section>
  );
}