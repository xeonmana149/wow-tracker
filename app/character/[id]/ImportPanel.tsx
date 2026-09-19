"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../../lib/supabase";
import { applyImport, type ParsedExport } from "../../../lib/importLogic";

type Profession = { id: string; profession: string; skill: number };

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
    try {
      const importResult = await applyImport(supabase, characterId, activeSpec, professions, parsed);
      setResult(parsed);
      setGearChanges(importResult.gearChanges);
      setTalentResult({ applied: importResult.talentApplied, unknown: importResult.talentUnknown });
      setMessage(
        "Imported. Level, gold, guild, stats, professions, gear and recognized talents are updated."
      );
      router.refresh();
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Import failed");
    } finally {
      setBusy(false);
    }
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