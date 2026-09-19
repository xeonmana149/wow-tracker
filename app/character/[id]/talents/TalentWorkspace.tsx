"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../../../lib/supabase";
import type { ClassData, Ranks } from "../../../../lib/talents";
import { adjustStats, buildBonus } from "../../../../lib/talent-effects";
import TalentPlanner from "./TalentPlanner";

type Slot = 1 | 2;
type Builds = { 1: Ranks; 2: Ranks };

export default function TalentWorkspace({
  characterId,
  ownerId,
  level,
  data,
  mainSpec,
  offSpec,
  initialActive,
  initialApplied,
  initialPlans,
  stats,
  hasStats,
}: {
  characterId: string;
  ownerId: string | null;
  level: number;
  data: ClassData;
  mainSpec: string | null;
  offSpec: string | null;
  initialActive: Slot;
  initialApplied: Builds;
  initialPlans: Builds;
  stats: Record<string, number>;
  hasStats: boolean;
}) {
  const router = useRouter();
  const [isOwner, setIsOwner] = useState(false);
  const [viewing, setViewing] = useState<Slot>(1);
  const [active, setActive] = useState<Slot>(initialActive);
  const [applied, setApplied] = useState<Builds>(initialApplied);
  const [savedStats, setSavedStats] = useState<Record<string, number>>(stats);
  const [switching, setSwitching] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    supabase.auth.getUser().then(({ data: userData }) => {
      setIsOwner(!!ownerId && userData.user?.id === ownerId);
    });
  }, [ownerId]);

  // The second build only exists once the character has an off spec
  const hasSecondary = !!offSpec;
  const view: Slot = hasSecondary ? viewing : 1;
  const activeSlot: Slot = hasSecondary ? active : 1;

  const tabs: { slot: Slot; label: string; spec: string | null }[] = [
    { slot: 1, label: "Primary", spec: mainSpec },
  ];
  if (hasSecondary) tabs.push({ slot: 2, label: "Secondary", spec: offSpec });

  async function makeActive(target: Slot) {
    if (target === activeSlot) return;
    setSwitching(true);
    setMessage("");

    const { error } = await supabase
      .from("characters")
      .update({ active_spec: target })
      .eq("id", characterId);

    if (error) {
      setMessage(
        `Couldn't change the active spec: ${error.message}. If this mentions a check constraint, open Edit Character and fill in every required box, then try again.`
      );
      setSwitching(false);
      return;
    }

    // Move the saved stats by the difference between the two applied builds
    if (hasStats) {
      const next = adjustStats(
        savedStats,
        buildBonus(data, applied[activeSlot]),
        buildBonus(data, applied[target])
      );
      const rows = Object.keys(next)
        .filter((k) => next[k] !== savedStats[k])
        .map((k) => ({ character_id: characterId, stat: k, value: next[k] }));

      if (rows.length > 0) {
        const { error: statError } = await supabase
          .from("character_stats")
          .upsert(rows, { onConflict: "character_id,stat" });
        if (statError) {
          setMessage(
            `The active spec changed, but your stats couldn't be updated: ${statError.message}. Re-enter them on the character page.`
          );
        } else {
          setSavedStats(next);
        }
      }
    }

    setActive(target);
    setSwitching(false);
    router.refresh();
  }

  const viewingTab = tabs.find((t) => t.slot === view) ?? tabs[0];

  return (
    <div>
      {hasSecondary ? (
        <div className="mb-4 flex flex-wrap gap-2">
          {tabs.map((t) => (
            <button
              key={t.slot}
              type="button"
              onClick={() => setViewing(t.slot)}
              className={`flex items-center gap-2 rounded border px-4 py-2 text-sm ${
                view === t.slot
                  ? "border-blue-500 bg-blue-600 text-white"
                  : "border-neutral-700 bg-neutral-800 text-gray-300"
              }`}
            >
              <span>
                {t.label}
                {t.spec ? ` · ${t.spec}` : ""}
              </span>
              {activeSlot === t.slot && (
                <span className="rounded bg-emerald-800 px-2 py-0.5 text-xs text-emerald-100">
                  Active
                </span>
              )}
            </button>
          ))}
        </div>
      ) : (
        isOwner && (
          <p className="mb-4 rounded bg-neutral-900 px-3 py-2 text-sm text-gray-400">
            Want to plan a second build? Set an off spec on this character&apos;s Edit page
            and a Secondary tab will appear here.
          </p>
        )
      )}

      {hasSecondary && isOwner && view !== activeSlot && (
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3 rounded bg-neutral-900 px-4 py-3 text-sm">
          <span className="text-gray-300">
            Your saved stats belong to your {tabs.find((t) => t.slot === activeSlot)?.label}{" "}
            spec. Switching moves them by the difference between the two applied builds.
          </span>
          <button
            type="button"
            onClick={() => makeActive(view)}
            disabled={switching}
            className="rounded bg-blue-600 px-4 py-2 text-white disabled:opacity-40"
          >
            {switching ? "Switching..." : `Make ${viewingTab.label} the active spec`}
          </button>
        </div>
      )}

      {message && <p className="mb-4 text-sm text-red-400">{message}</p>}

      {tabs.map((t) => (
        <div key={t.slot} className={view === t.slot ? "" : "hidden"}>
          <TalentPlanner
            slot={t.slot}
            isActive={activeSlot === t.slot}
            characterId={characterId}
            ownerId={ownerId}
            level={level}
            data={data}
            applied={applied[t.slot]}
            otherApplied={applied[t.slot === 1 ? 2 : 1]}
            initialPlan={initialPlans[t.slot]}
            savedStats={savedStats}
            hasStats={hasStats}
            onApplied={(ranks) => setApplied((prev) => ({ ...prev, [t.slot]: ranks }))}
            onStats={setSavedStats}
          />
        </div>
      ))}
    </div>
  );
}