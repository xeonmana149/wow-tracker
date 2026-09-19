"use client";

import {
  useEffect,
  useMemo,
  useState,
  type CSSProperties,
  type MouseEvent,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../../../lib/supabase";
import {
  type ClassData,
  type Ranks,
  type Talent,
  type Tree,
  MAX_POINTS,
  availability,
  canLearn,
  canUnlearn,
  descFor,
  keyOf,
  pointsForLevel,
  rankOf,
  totalPoints,
  treePoints,
} from "../../../../lib/talents";
import { adjustStats, buildBonus } from "../../../../lib/talent-effects";
import StatPanel from "./StatPanel";

const TILE = 46;
const GAP_X = 14;
const GAP_Y = 18;

// Just a tint behind each tree, since we don't have the game's artwork
const PANEL_BG = [
  "linear-gradient(180deg, rgba(133, 90, 20, 0.35), rgba(12, 12, 12, 0.95) 70%)",
  "linear-gradient(180deg, rgba(40, 90, 140, 0.35), rgba(12, 12, 12, 0.95) 70%)",
  "linear-gradient(180deg, rgba(110, 60, 140, 0.35), rgba(12, 12, 12, 0.95) 70%)",
];

function initials(name: string) {
  return name
    .split(/[\s-]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0])
    .join("")
    .toUpperCase();
}

// True if the two builds are not identical
function differs(a: Ranks, b: Ranks) {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const k of keys) {
    if ((a[k] ?? 0) !== (b[k] ?? 0)) return true;
  }
  return false;
}

function TalentIcon({ icon, name, gray }: { icon: string; name: string; gray: boolean }) {
  const [failed, setFailed] = useState(false);

  if (failed) {
    return (
      <span
        className={`flex h-full w-full items-center justify-center bg-neutral-800 text-sm font-bold ${
          gray ? "text-gray-500" : "text-amber-200"
        }`}
      >
        {initials(name)}
      </span>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={`/talent-icons/${icon}.jpg`}
      alt={name}
      draggable={false}
      onError={() => setFailed(true)}
      className={`h-full w-full object-cover ${gray ? "opacity-40 grayscale" : ""}`}
    />
  );
}

// A box that follows the mouse, and flips to the other side near the screen edges
function FloatingTip({
  start,
  children,
}: {
  start: { x: number; y: number };
  children: ReactNode;
}) {
  const [pos, setPos] = useState(start);

  useEffect(() => {
    function onMove(e: globalThis.MouseEvent) {
      setPos({ x: e.clientX, y: e.clientY });
    }
    window.addEventListener("mousemove", onMove);
    return () => window.removeEventListener("mousemove", onMove);
  }, []);

  const style: CSSProperties = {};
  if (pos.x > window.innerWidth - 380) style.right = window.innerWidth - pos.x + 16;
  else style.left = pos.x + 16;
  if (pos.y > window.innerHeight - 340) style.bottom = window.innerHeight - pos.y + 16;
  else style.top = pos.y + 16;

  return (
    <div
      className="pointer-events-none fixed z-50 w-[340px] max-w-[90vw] rounded-md border border-neutral-400 bg-black/95 p-3 shadow-xl"
      style={style}
    >
      {children}
    </div>
  );
}

export default function TalentPlanner({
  characterId,
  ownerId,
  level,
  data,
  slot,
  isActive,
  applied,
  otherApplied,
  initialPlan,
  savedStats,
  hasStats,
  onApplied,
  onStats,
}: {
  characterId: string;
  ownerId: string | null;
  level: number;
  data: ClassData;
  slot: 1 | 2;
  isActive: boolean; // is this the spec the character is playing right now?
  applied: Ranks; // this spec's applied build
  otherApplied: Ranks; // the other spec's applied build
  initialPlan: Ranks;
  savedStats: Record<string, number>; // belong to the active spec
  hasStats: boolean;
  onApplied: (ranks: Ranks) => void;
  onStats: (stats: Record<string, number>) => void;
}) {
  const router = useRouter();
  const [isOwner, setIsOwner] = useState(false);
  const [mode, setMode] = useState<"live" | "plan">("live");

  // Pending points aren't saved until Apply. Applied points are permanent, like in the game.
  const [pending, setPending] = useState<Ranks>(applied);

  // Plan: a sandbox. With no saved plan, it starts as a copy of the applied build.
  const [savedPlan, setSavedPlan] = useState<Ranks>(initialPlan);
  const [plan, setPlan] = useState<Ranks>(() =>
    Object.keys(initialPlan).length > 0 ? initialPlan : applied
  );

  const [hover, setHover] = useState<{
    tree: string;
    talent: string;
    x: number;
    y: number;
  } | null>(null);
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    supabase.auth.getUser().then(({ data: userData }) => {
      setIsOwner(!!ownerId && userData.user?.id === ownerId);
    });
  }, [ownerId]);

  const isPlan = mode === "plan";
  const ranks = isPlan ? plan : pending;
  const setRanks = isPlan ? setPlan : setPending;
  const budget = isPlan ? MAX_POINTS : pointsForLevel(level);
  const locked: Ranks = isPlan ? {} : applied;
  const canEdit = isPlan || isOwner;
  const spent = totalPoints(data, ranks);
  const left = budget - spent;
  const liveDirty = differs(applied, pending);
  const planDirty = differs(savedPlan, plan);
  const hasSavedPlan = Object.keys(savedPlan).length > 0;

  // Your saved stats include the talents of the ACTIVE spec's applied build.
  // The stats shown are those numbers, changed by the difference to the build on screen.
  const referenceApplied = isActive ? applied : otherApplied;
  const referenceBonus = useMemo(
    () => buildBonus(data, referenceApplied),
    [data, referenceApplied]
  );
  const shownBonus = useMemo(() => buildBonus(data, ranks), [data, ranks]);
  const shownStats = adjustStats(savedStats, referenceBonus, shownBonus);

  // Grid size, based on the biggest tree
  const allTalents = data.trees.flatMap((t) => t.talents);
  const rowCount = Math.max(...allTalents.map((t) => t.row));
  const colCount = Math.max(4, ...allTalents.map((t) => t.col));
  const gridW = colCount * TILE + (colCount - 1) * GAP_X;
  const gridH = rowCount * TILE + (rowCount - 1) * GAP_Y;
  const cx = (col: number) => (col - 1) * (TILE + GAP_X) + TILE / 2;
  const cy = (row: number) => (row - 1) * (TILE + GAP_Y) + TILE / 2;

  function switchMode(next: "live" | "plan") {
    setMode(next);
    setMessage("");
    setHover(null);
  }

  function learn(tree: Tree, talent: Talent) {
    if (!canEdit) return;
    const check = canLearn(tree, talent, ranks, left);
    if (!check.ok) {
      setMessage(check.reason);
      return;
    }
    setMessage("");
    setRanks({ ...ranks, [keyOf(tree, talent)]: rankOf(ranks, tree, talent) + 1 });
  }

  function unlearn(tree: Tree, talent: Talent) {
    if (!canEdit) return;
    const check = canUnlearn(tree, talent, ranks, locked);
    if (!check.ok) {
      setMessage(check.reason);
      return;
    }
    setMessage("");
    const key = keyOf(tree, talent);
    const next = { ...ranks };
    const rank = (next[key] ?? 0) - 1;
    if (rank <= 0) delete next[key];
    else next[key] = rank;
    setRanks(next);
  }

  function handleClick(e: MouseEvent<HTMLButtonElement>, tree: Tree, talent: Talent) {
    if (e.shiftKey) unlearn(tree, talent);
    else learn(tree, talent);
  }

  // Rows to write for talents whose rank differs from `before`
  function changedRows(after: Ranks, before: Ranks) {
    const rows: {
      character_id: string;
      slot: number;
      tree: string;
      talent: string;
      rank: number;
    }[] = [];
    for (const tree of data.trees) {
      for (const talent of tree.talents) {
        const key = keyOf(tree, talent);
        const rank = after[key] ?? 0;
        if (rank > 0 && rank !== (before[key] ?? 0)) {
          rows.push({
            character_id: characterId,
            slot,
            tree: tree.name,
            talent: talent.name,
            rank,
          });
        }
      }
    }
    return rows;
  }

  // Keep the saved stats matching the applied talents. Returns an error message, or null.
  async function saveStats(next: Record<string, number>) {
    const rows = Object.keys(next)
      .filter((k) => next[k] !== savedStats[k])
      .map((k) => ({ character_id: characterId, stat: k, value: next[k] }));
    if (rows.length === 0) return null;

    const { error } = await supabase
      .from("character_stats")
      .upsert(rows, { onConflict: "character_id,stat" });
    return error ? error.message : null;
  }

  async function handleApply() {
    setSaving(true);
    setMessage("");

    const rows = changedRows(pending, applied);
    if (rows.length > 0) {
      const { error } = await supabase
        .from("character_talents")
        .upsert(rows, { onConflict: "character_id,slot,tree,talent" });
      if (error) {
        setMessage(error.message);
        setSaving(false);
        return;
      }
    }

    // Stats belong to the active spec, so only its changes move them
    let note = "";
    if (hasStats && isActive) {
      const next = adjustStats(savedStats, referenceBonus, buildBonus(data, pending));
      const problem = await saveStats(next);
      if (problem) note = `Talents applied, but your stats couldn't be updated: ${problem}`;
      else onStats(next);
    }

    onApplied(pending);
    setSaving(false);
    if (note) setMessage(note);
    router.refresh();
  }

  async function handleRespec() {
    if (!confirm("Reset every talent in this build? This clears all its applied points.")) return;

    setSaving(true);
    const { error } = await supabase
      .from("character_talents")
      .delete()
      .eq("character_id", characterId)
      .eq("slot", slot);

    if (error) {
      setMessage(error.message);
      setSaving(false);
      return;
    }

    let note = "";
    if (hasStats && isActive) {
      const next = adjustStats(savedStats, referenceBonus, buildBonus(data, {}));
      const problem = await saveStats(next);
      if (problem) note = `Talents reset, but your stats couldn't be updated: ${problem}`;
      else onStats(next);
    }

    onApplied({});
    setPending({});
    setSaving(false);
    setMessage(note);
    router.refresh();
  }

  async function handleSavePlan() {
    setSaving(true);
    setMessage("");

    const rows = changedRows(plan, savedPlan);
    if (rows.length > 0) {
      const { error } = await supabase
        .from("character_talent_plans")
        .upsert(rows, { onConflict: "character_id,slot,tree,talent" });
      if (error) {
        setMessage(error.message);
        setSaving(false);
        return;
      }
    }

    // Remove talents that were in the saved plan but aren't any more
    for (const tree of data.trees) {
      for (const talent of tree.talents) {
        const key = keyOf(tree, talent);
        if ((savedPlan[key] ?? 0) > 0 && (plan[key] ?? 0) === 0) {
          const { error } = await supabase
            .from("character_talent_plans")
            .delete()
            .eq("character_id", characterId)
            .eq("slot", slot)
            .eq("tree", tree.name)
            .eq("talent", talent.name);
          if (error) {
            setMessage(error.message);
            setSaving(false);
            return;
          }
        }
      }
    }

    setSavedPlan(plan);
    setSaving(false);
    router.refresh();
  }

  // What the tooltip shows
  const hTree = hover ? data.trees.find((t) => t.name === hover.tree) : undefined;
  const hTalent = hTree?.talents.find((t) => t.name === hover?.talent);
  const hRank = hTree && hTalent ? rankOf(ranks, hTree, hTalent) : 0;
  const hLock = hTree && hTalent ? availability(hTree, hTalent, ranks) : null;
  const hShown = hTalent ? descFor(hTalent, Math.max(1, hRank)) : null;
  const hNext =
    hTalent && hRank > 0 && hRank < hTalent.max ? descFor(hTalent, hRank + 1) : null;
  const hCanLearn = hTree && hTalent ? canLearn(hTree, hTalent, ranks, left).ok : false;
  const hCanUnlearn = hTree && hTalent ? canUnlearn(hTree, hTalent, ranks, locked).ok : false;

  return (
    <div className="flex flex-col gap-4 xl:flex-row xl:items-start">
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center justify-between gap-3 rounded bg-neutral-900 px-4 py-3">
          <div className="flex flex-wrap items-center gap-3">
            <div className="flex overflow-hidden rounded border border-neutral-700 text-sm">
              <button
                type="button"
                onClick={() => switchMode("live")}
                className={`px-4 py-1.5 ${
                  !isPlan ? "bg-blue-600 text-white" : "bg-neutral-800 text-gray-300"
                }`}
              >
                Live build
              </button>
              <button
                type="button"
                onClick={() => switchMode("plan")}
                className={`px-4 py-1.5 ${
                  isPlan ? "bg-blue-600 text-white" : "bg-neutral-800 text-gray-300"
                }`}
              >
                Plan
              </button>
            </div>
            <span className="text-sm text-gray-400">
              {isPlan ? "Plan" : `Level ${level}`} · {budget} talent points
            </span>
          </div>
          <div className="flex items-center gap-3">
            <span className="text-amber-100">Unspent Talents</span>
            <span className="rounded border border-amber-800 bg-neutral-950 px-5 py-1 text-2xl font-bold">
              {Math.max(0, left)}
            </span>
          </div>
        </div>

        {isPlan && (
          <p className="mt-2 rounded bg-blue-950 px-3 py-2 text-sm text-blue-200">
            Plan mode: try any build with all {MAX_POINTS} points. Nothing here changes the
            character&apos;s real talents.
          </p>
        )}

        {!isActive && (
          <p className="mt-2 rounded bg-neutral-900 px-3 py-2 text-sm text-gray-300">
            This isn&apos;t the active spec. The stats show what you&apos;d have if you
            switched to it, and applying talents here doesn&apos;t change your saved stats.
          </p>
        )}

        {!isPlan && left < 0 && (
          <p className="mt-2 text-sm text-yellow-500">
            This build uses more points than a level {level} character has. Check the
            character&apos;s level.
          </p>
        )}

        <div className="mt-4 flex flex-col gap-3 xl:flex-row">
          {data.trees.map((tree, ti) => (
            <section
              key={tree.name}
              className="flex-1 overflow-x-auto rounded border border-neutral-800 p-3"
              style={{ background: PANEL_BG[ti % PANEL_BG.length] }}
            >
              <header className="flex items-center gap-3">
                <div className="relative h-14 w-14 shrink-0">
                  <div className="h-full w-full overflow-hidden rounded-full border-2 border-amber-700">
                    <TalentIcon icon={tree.icon} name={tree.name} gray={false} />
                  </div>
                  <span className="absolute -bottom-1 -right-1 rounded border border-amber-700 bg-neutral-900 px-1.5 text-xs font-bold text-amber-300">
                    {treePoints(tree, ranks)}
                  </span>
                </div>
                <h2 className="text-xl font-bold text-amber-50">{tree.name}</h2>
              </header>

              <div className="relative mx-auto mt-5" style={{ width: gridW, height: gridH }}>
                <svg
                  className="pointer-events-none absolute inset-0"
                  width={gridW}
                  height={gridH}
                >
                  <defs>
                    <marker
                      id={`arrow-on-${slot}-${ti}`}
                      markerWidth="10"
                      markerHeight="10"
                      refX="8"
                      refY="5"
                      orient="auto"
                      markerUnits="userSpaceOnUse"
                    >
                      <path d="M0,0 L10,5 L0,10 z" fill="#d4a72c" />
                    </marker>
                    <marker
                      id={`arrow-off-${slot}-${ti}`}
                      markerWidth="10"
                      markerHeight="10"
                      refX="8"
                      refY="5"
                      orient="auto"
                      markerUnits="userSpaceOnUse"
                    >
                      <path d="M0,0 L10,5 L0,10 z" fill="#6b7280" />
                    </marker>
                  </defs>

                  {tree.talents.map((talent) => {
                    if (!talent.req) return null;
                    const from = tree.talents.find((t) => t.name === talent.req);
                    if (!from) return null;

                    const dx = cx(talent.col) - cx(from.col);
                    const dy = cy(talent.row) - cy(from.row);
                    const len = Math.hypot(dx, dy);
                    const pad = TILE / 2 + 3;
                    if (len <= pad * 2) return null;

                    const ux = dx / len;
                    const uy = dy / len;
                    const on = rankOf(ranks, tree, from) >= from.max;

                    return (
                      <line
                        key={talent.name}
                        x1={cx(from.col) + ux * pad}
                        y1={cy(from.row) + uy * pad}
                        x2={cx(talent.col) - ux * pad}
                        y2={cy(talent.row) - uy * pad}
                        stroke={on ? "#d4a72c" : "#6b7280"}
                        strokeWidth={3}
                        markerEnd={`url(#arrow-${on ? "on" : "off"}-${slot}-${ti})`}
                      />
                    );
                  })}
                </svg>

                {tree.talents.map((talent) => {
                  const rank = rankOf(ranks, tree, talent);
                  const open = availability(tree, talent, ranks).ok;
                  const learnable = open && rank < talent.max && left > 0;
                  const status =
                    rank >= talent.max
                      ? "maxed"
                      : rank > 0
                      ? "partial"
                      : learnable
                      ? "open"
                      : "locked";

                  const border = {
                    maxed: "border-yellow-400",
                    partial: "border-green-500",
                    open: "border-neutral-200",
                    locked: "border-neutral-700",
                  }[status];

                  const badge = status === "maxed" ? "text-yellow-300" : "text-green-400";

                  return (
                    <button
                      key={talent.name}
                      type="button"
                      onMouseEnter={(e) =>
                        setHover({
                          tree: tree.name,
                          talent: talent.name,
                          x: e.clientX,
                          y: e.clientY,
                        })
                      }
                      onMouseLeave={() => setHover(null)}
                      onClick={(e) => handleClick(e, tree, talent)}
                      onContextMenu={(e) => {
                        e.preventDefault();
                        unlearn(tree, talent);
                      }}
                      className={`absolute overflow-hidden rounded-md border-2 bg-neutral-900 ${border}`}
                      style={{
                        width: TILE,
                        height: TILE,
                        left: (talent.col - 1) * (TILE + GAP_X),
                        top: (talent.row - 1) * (TILE + GAP_Y),
                      }}
                    >
                      <TalentIcon
                        icon={talent.icon}
                        name={talent.name}
                        gray={status === "locked"}
                      />
                      {(rank > 0 || status === "open") && (
                        <span
                          className={`absolute bottom-0 right-0.5 text-sm font-bold [text-shadow:0_0_3px_#000,0_0_3px_#000] ${badge}`}
                        >
                          {rank}
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>
            </section>
          ))}
        </div>

        <div className="mt-4 flex flex-wrap items-center justify-center gap-3">
          {isPlan ? (
            <>
              {isOwner && (
                <button
                  onClick={handleSavePlan}
                  disabled={!planDirty || saving}
                  className="rounded border border-amber-700 bg-neutral-800 px-8 py-2 text-amber-100 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  {saving ? "Saving..." : "Save plan"}
                </button>
              )}
              <button
                onClick={() => {
                  setPlan({ ...applied });
                  setMessage("");
                }}
                className="rounded bg-neutral-700 px-4 py-2 text-white"
              >
                Start from applied build
              </button>
              <button
                onClick={() => {
                  setPlan({});
                  setMessage("");
                }}
                className="rounded bg-neutral-700 px-4 py-2 text-white"
              >
                Clear plan
              </button>
              {planDirty && hasSavedPlan && (
                <button
                  onClick={() => {
                    setPlan(savedPlan);
                    setMessage("");
                  }}
                  className="rounded bg-neutral-700 px-4 py-2 text-white"
                >
                  Revert to saved plan
                </button>
              )}
            </>
          ) : isOwner ? (
            <>
              <button
                onClick={handleApply}
                disabled={!liveDirty || saving}
                className="rounded border border-amber-700 bg-neutral-800 px-8 py-2 text-amber-100 disabled:cursor-not-allowed disabled:opacity-40"
              >
                {saving ? "Saving..." : "Apply Changes"}
              </button>
              {liveDirty && (
                <button
                  onClick={() => {
                    setPending(applied);
                    setMessage("");
                  }}
                  className="rounded bg-neutral-700 px-4 py-2 text-white"
                >
                  Discard changes
                </button>
              )}
              <button
                onClick={handleRespec}
                disabled={saving}
                className="rounded bg-red-800 px-4 py-2 text-white disabled:opacity-40"
              >
                Respec
              </button>
            </>
          ) : (
            <p className="text-sm text-gray-400">
              You&apos;re viewing this character&apos;s talents. Switch to Plan to try builds.
            </p>
          )}
        </div>

        <p className="mt-2 text-center text-xs text-gray-500">
          {isPlan
            ? isOwner
              ? "Left-click adds a point, right-click or Shift-click removes one. Save plan keeps it so friends can see it in Plan mode."
              : "Left-click adds a point, right-click or Shift-click removes one. Only the owner can save a plan, so your changes disappear when you leave."
            : isOwner
            ? isActive
              ? "Left-click adds a point. Right-click or Shift-click removes one. Applied points are permanent, like in the game, and Apply Changes also updates your saved stats."
              : "Left-click adds a point. Right-click or Shift-click removes one. Applied points are permanent, like in the game."
            : ""}
        </p>

        {message && <p className="mt-3 text-center text-sm text-red-400">{message}</p>}
      </div>

        <div className="w-full xl:sticky xl:top-4 xl:w-[430px] xl:shrink-0">
        <StatPanel
          shown={shownStats}
          saved={savedStats}
          estimated={shownBonus.estimated}
          hasStats={hasStats}
          characterId={characterId}
          isPlan={isPlan}
        />
      </div>

      {hover && hTree && hTalent && (
        <FloatingTip start={{ x: hover.x, y: hover.y }}>
          <div className="text-base font-bold text-white">{hTalent.name}</div>
          <div className="text-sm text-white">
            Rank {hRank}/{hTalent.max}
          </div>
          <div className="mt-2 text-sm text-white">{hTalent.passive ? "Passive" : "Active"}</div>
          {hTalent.cost && <div className="text-sm text-white">{hTalent.cost}</div>}

          {hShown && (
            <p className="mt-1 whitespace-pre-line text-sm text-[#ffd100]">{hShown.text}</p>
          )}
          {hShown && !hShown.exact && (
            <p className="text-xs italic text-gray-400">
              Rank {Math.max(1, hRank)} isn&apos;t recorded yet, showing rank {hShown.shownRank}.
            </p>
          )}

          {hNext && (
            <>
              <div className="mt-3 text-sm text-white">Next rank:</div>
              <p className="whitespace-pre-line text-sm text-[#ffd100]">{hNext.text}</p>
              {!hNext.exact && (
                <p className="text-xs italic text-gray-400">
                  Rank {hRank + 1} isn&apos;t recorded yet, showing rank {hNext.shownRank}.
                </p>
              )}
            </>
          )}

          {hLock && !hLock.ok && <p className="mt-3 text-sm text-red-500">{hLock.reason}</p>}
          {hTalent.reqText && <p className="mt-1 text-sm text-red-500">{hTalent.reqText}</p>}

          {hTalent.isNew && <p className="mt-2 text-xs text-emerald-400">New in Forever</p>}
          {!hTalent.complete && (
            <p className="mt-1 text-xs text-gray-500">
              Some ranks haven&apos;t been confirmed from the beta client yet.
            </p>
          )}

          {canEdit && hCanLearn && <p className="mt-2 text-sm text-green-400">Click to learn</p>}
          {canEdit && hCanUnlearn && (
            <p className="text-xs text-gray-400">Right-click to unlearn</p>
          )}
        </FloatingTip>
      )}
    </div>
  );
}