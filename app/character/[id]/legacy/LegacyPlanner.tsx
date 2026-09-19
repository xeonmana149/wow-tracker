"use client";

import { useEffect, useState, type MouseEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "../../../../lib/supabase";
import { norm } from "../../../../lib/icons";
import {
  LEGACY_CAP,
  LEGACY_TREES,
  LEGACY_TREE_ICONS,
  LEGACY_PERK_ICONS,
  LEGACY_FALLBACK_DESC,
  canLearnPerk,
  canUnlearnPerk,
  legacyAvailability,
  legacyKey,
  legacyRank,
  legacyTotal,
  legacyTreePoints,
  type LegacyPerk,
  type LegacyRanks,
  type LegacyTree,
} from "../../../../lib/legacy";
import FloatingTip from "../../../FloatingTip";

const TILE = 56;
const GAP_X = 22;
const GAP_Y = 30;
const COLS = 4;
const ROWS = 3;
const LABEL_W = 44;

const gridW = COLS * TILE + (COLS - 1) * GAP_X;
const gridH = ROWS * TILE + (ROWS - 1) * GAP_Y;
const cx = (col: number) => (col - 1) * (TILE + GAP_X) + TILE / 2;
const cy = (row: number) => row * (TILE + GAP_Y) + TILE / 2;

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
function differs(a: LegacyRanks, b: LegacyRanks) {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const k of keys) {
    if ((a[k] ?? 0) !== (b[k] ?? 0)) return true;
  }
  return false;
}

function PerkIcon({ icon, name, gray }: { icon?: string; name: string; gray: boolean }) {
  const [failed, setFailed] = useState(false);

  if (!icon || failed) {
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

export default function LegacyPlanner({
  characterId,
  ownerId,
  earned,
  perkInfo,
  treeIcons,
  initialApplied,
  initialPlan,
}: {
  characterId: string;
  ownerId: string | null;
  earned: number; // legacy points this account has earned
  perkInfo: Record<string, { desc: string; icon: string }>;
  treeIcons: Record<string, string>;
  initialApplied: LegacyRanks;
  initialPlan: LegacyRanks;
}) {
  const router = useRouter();
  const [isOwner, setIsOwner] = useState(false);
  const [mode, setMode] = useState<"live" | "plan">("live");

  // Pending points aren't saved until Apply. Applied points are permanent, like talents.
  const [applied, setApplied] = useState<LegacyRanks>(initialApplied);
  const [pending, setPending] = useState<LegacyRanks>(initialApplied);

  // Plan: a sandbox. With no saved plan, it starts as a copy of the applied build.
  const [savedPlan, setSavedPlan] = useState<LegacyRanks>(initialPlan);
  const [plan, setPlan] = useState<LegacyRanks>(() =>
    Object.keys(initialPlan).length > 0 ? initialPlan : initialApplied
  );

  const [hover, setHover] = useState<{
    tree: string;
    perk: string;
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
  const budget = isPlan ? LEGACY_CAP : Math.min(LEGACY_CAP, earned);
  const locked: LegacyRanks = isPlan ? {} : applied;
  const canEdit = isPlan || isOwner;
  const spent = legacyTotal(ranks);
  const left = budget - spent;
  const liveDirty = differs(applied, pending);
  const planDirty = differs(savedPlan, plan);
  const hasSavedPlan = Object.keys(savedPlan).length > 0;

  function switchMode(next: "live" | "plan") {
    setMode(next);
    setMessage("");
    setHover(null);
  }

  function learn(tree: LegacyTree, perk: LegacyPerk) {
    if (!canEdit) return;
    const check = canLearnPerk(tree, perk, ranks, left);
    if (!check.ok) {
      setMessage(check.reason);
      return;
    }
    setMessage("");
    setRanks({ ...ranks, [legacyKey(tree, perk)]: legacyRank(ranks, tree, perk) + 1 });
  }

  function unlearn(tree: LegacyTree, perk: LegacyPerk) {
    if (!canEdit) return;
    const check = canUnlearnPerk(tree, perk, ranks, locked);
    if (!check.ok) {
      setMessage(check.reason);
      return;
    }
    setMessage("");
    const key = legacyKey(tree, perk);
    const next = { ...ranks };
    const rank = (next[key] ?? 0) - 1;
    if (rank <= 0) delete next[key];
    else next[key] = rank;
    setRanks(next);
  }

  function handleClick(e: MouseEvent<HTMLButtonElement>, tree: LegacyTree, perk: LegacyPerk) {
    if (e.shiftKey) unlearn(tree, perk);
    else learn(tree, perk);
  }

  // Rows to write for perks whose rank differs from `before`
  function changedRows(after: LegacyRanks, before: LegacyRanks) {
    const rows: { character_id: string; tree: string; perk: string; rank: number }[] = [];
    for (const tree of LEGACY_TREES) {
      for (const perk of tree.perks) {
        const key = legacyKey(tree, perk);
        const rank = after[key] ?? 0;
        if (rank > 0 && rank !== (before[key] ?? 0)) {
          rows.push({ character_id: characterId, tree: tree.name, perk: perk.name, rank });
        }
      }
    }
    return rows;
  }

  async function handleApply() {
    setSaving(true);
    setMessage("");

    const rows = changedRows(pending, applied);
    if (rows.length > 0) {
      const { error } = await supabase
        .from("character_legacy")
        .upsert(rows, { onConflict: "character_id,tree,perk" });
      if (error) {
        setMessage(error.message);
        setSaving(false);
        return;
      }
    }

    setApplied(pending);
    setSaving(false);
    router.refresh();
  }

  async function handleRespec() {
    if (!confirm("Reset every legacy perk on this character? This clears all applied points.")) {
      return;
    }

    setSaving(true);
    const { error } = await supabase
      .from("character_legacy")
      .delete()
      .eq("character_id", characterId);
    setSaving(false);

    if (error) {
      setMessage(error.message);
      return;
    }
    setApplied({});
    setPending({});
    setMessage("");
    router.refresh();
  }

  async function handleSavePlan() {
    setSaving(true);
    setMessage("");

    const rows = changedRows(plan, savedPlan);
    if (rows.length > 0) {
      const { error } = await supabase
        .from("character_legacy_plans")
        .upsert(rows, { onConflict: "character_id,tree,perk" });
      if (error) {
        setMessage(error.message);
        setSaving(false);
        return;
      }
    }

    // Remove perks that were in the saved plan but aren't any more
    for (const tree of LEGACY_TREES) {
      for (const perk of tree.perks) {
        const key = legacyKey(tree, perk);
        if ((savedPlan[key] ?? 0) > 0 && (plan[key] ?? 0) === 0) {
          const { error } = await supabase
            .from("character_legacy_plans")
            .delete()
            .eq("character_id", characterId)
            .eq("tree", tree.name)
            .eq("perk", perk.name);
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
  const hTree = hover ? LEGACY_TREES.find((t) => t.name === hover.tree) : undefined;
  const hPerk = hTree?.perks.find((p) => p.name === hover?.perk);
  const hRank = hTree && hPerk ? legacyRank(ranks, hTree, hPerk) : 0;
  const hInfo = hPerk ? perkInfo[norm(hPerk.name)] : undefined;
  const hOthers = hTree && hPerk ? legacyTreePoints(hTree, ranks) - hRank : 0;
  const hReq = hTree && hPerk?.req ? hTree.perks.find((p) => p.name === hPerk.req) : undefined;
  const hCanLearn = hTree && hPerk ? canLearnPerk(hTree, hPerk, ranks, left).ok : false;
  const hCanUnlearn = hTree && hPerk ? canUnlearnPerk(hTree, hPerk, ranks, locked).ok : false;

  return (
    <div>
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
            {isPlan
              ? `Plan · ${LEGACY_CAP} legacy points`
              : `${Math.min(LEGACY_CAP, earned)} of ${LEGACY_CAP} points earned on this account`}
          </span>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-amber-100">Unspent Legacy Points</span>
          <span className="rounded border border-amber-800 bg-neutral-950 px-5 py-1 text-2xl font-bold">
            {Math.max(0, left)}
          </span>
        </div>
      </div>

      {isPlan && (
        <p className="mt-2 rounded bg-blue-950 px-3 py-2 text-sm text-blue-200">
          Plan mode: try any build with all {LEGACY_CAP} points. Nothing here changes the
          character&apos;s real legacy perks.
        </p>
      )}

      {!isPlan && earned <= 0 && (
        <p className="mt-2 rounded bg-neutral-900 px-3 py-2 text-sm text-gray-300">
          This account has no legacy points yet.{" "}
          {isOwner ? (
            <>
              Set how many you&apos;ve earned in the Legacy points box on your{" "}
              <Link href="/" className="text-blue-400 underline">
                dashboard
              </Link>
              , or use Plan to try a build.
            </>
          ) : (
            "Switch to Plan to try a build."
          )}
        </p>
      )}

      {!isPlan && left < 0 && (
        <p className="mt-2 text-sm text-yellow-500">
          This build uses more points than the account has earned. Check the Legacy points on the
          dashboard.
        </p>
      )}

      <div className="mt-4 flex flex-col gap-3 lg:flex-row">
        {LEGACY_TREES.map((tree, ti) => (
          <section
            key={tree.name}
            className="flex-1 overflow-x-auto rounded border border-neutral-800 p-3"
            style={{ background: PANEL_BG[ti % PANEL_BG.length] }}
          >
            <header className="flex items-center gap-3">
              <div className="relative h-14 w-14 shrink-0">
                <div className="h-full w-full overflow-hidden rounded-full border-2 border-amber-700">
                    <PerkIcon
                    icon={LEGACY_TREE_ICONS[tree.name] ?? treeIcons[tree.name]}
                    name={tree.name}
                    gray={false}
                  />
                </div>
                <span className="absolute -bottom-1 -right-1 rounded border border-amber-700 bg-neutral-900 px-1.5 text-xs font-bold text-amber-300">
                  {legacyTreePoints(tree, ranks)}
                </span>
              </div>
              <h2 className="text-xl font-bold text-amber-50">{tree.name}</h2>
            </header>

            <div
              className="relative mx-auto mt-5"
              style={{ width: gridW + LABEL_W, height: gridH }}
            >
              {[0, 1, 2].map((row) => (
                <div
                  key={row}
                  className="absolute text-[11px] text-gray-500"
                  style={{ left: 0, top: row * (TILE + GAP_Y) + TILE / 2 - 8 }}
                  title="Points needed in this tree from other perks"
                >
                  {row === 0 ? "Open" : `${row * 5} pts`}
                </div>
              ))}

              <svg
                className="pointer-events-none absolute top-0"
                style={{ left: LABEL_W }}
                width={gridW}
                height={gridH}
              >
                <defs>
                  <marker
                    id={`lg-arrow-on-${ti}`}
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
                    id={`lg-arrow-off-${ti}`}
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

                {tree.perks.map((perk) => {
                  if (!perk.req) return null;
                  const from = tree.perks.find((p) => p.name === perk.req);
                  if (!from) return null;

                  const x1 = cx(from.col);
                  const y1 = cy(from.gate / 5);
                  const x2 = cx(perk.col);
                  const y2 = cy(perk.gate / 5);
                  const dx = x2 - x1;
                  const dy = y2 - y1;
                  const len = Math.hypot(dx, dy);
                  const pad = TILE / 2 + 3;
                  if (len <= pad * 2) return null;

                  const ux = dx / len;
                  const uy = dy / len;
                  const on = legacyRank(ranks, tree, from) >= from.max;

                  return (
                    <line
                      key={perk.name}
                      x1={x1 + ux * pad}
                      y1={y1 + uy * pad}
                      x2={x2 - ux * pad}
                      y2={y2 - uy * pad}
                      stroke={on ? "#d4a72c" : "#6b7280"}
                      strokeWidth={3}
                      markerEnd={`url(#lg-arrow-${on ? "on" : "off"}-${ti})`}
                    />
                  );
                })}
              </svg>

              {tree.perks.map((perk) => {
                const rank = legacyRank(ranks, tree, perk);
                const open = legacyAvailability(tree, perk, ranks).ok;
                const learnable = open && rank < perk.max && left > 0;
                const status =
                  rank >= perk.max
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
                    key={perk.name}
                    type="button"
                    onMouseEnter={(e) =>
                      setHover({
                        tree: tree.name,
                        perk: perk.name,
                        x: e.clientX,
                        y: e.clientY,
                      })
                    }
                    onMouseLeave={() => setHover(null)}
                    onClick={(e) => handleClick(e, tree, perk)}
                    onContextMenu={(e) => {
                      e.preventDefault();
                      unlearn(tree, perk);
                    }}
                    className={`absolute overflow-hidden rounded-md border-2 bg-neutral-900 ${border}`}
                    style={{
                      width: TILE,
                      height: TILE,
                      left: LABEL_W + (perk.col - 1) * (TILE + GAP_X),
                      top: (perk.gate / 5) * (TILE + GAP_Y),
                    }}
                  >
                    <PerkIcon
                      icon={LEGACY_PERK_ICONS[perk.name] ?? perkInfo[norm(perk.name)]?.icon}
                      name={perk.name}
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

            <p className="mt-3 text-xs text-gray-500">
              {tree.hidden} more perks in this tree aren&apos;t published yet.
            </p>
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
            You&apos;re viewing this character&apos;s legacy perks. Switch to Plan to try builds.
          </p>
        )}
      </div>

      <p className="mt-2 text-center text-xs text-gray-500">
        {isPlan
          ? isOwner
            ? "Left-click adds a point, right-click or Shift-click removes one. Save plan keeps it so friends can see it in Plan mode."
            : "Left-click adds a point, right-click or Shift-click removes one. Only the owner can save a plan, so your changes disappear when you leave."
          : isOwner
          ? "Left-click adds a point. Right-click or Shift-click removes one. Applied points are permanent, like talents."
          : ""}
      </p>

      {message && <p className="mt-3 text-center text-sm text-red-400">{message}</p>}

      {hover && hTree && hPerk && (
        <FloatingTip start={{ x: hover.x, y: hover.y }}>
          <div className="text-base font-bold text-white">{hPerk.name}</div>
          <div className="text-sm text-white">
            Rank {hRank}/{hPerk.max}
          </div>

          <p className="mt-2 whitespace-pre-line text-sm text-[#ffd100]">
            {hInfo?.desc ?? LEGACY_FALLBACK_DESC[hPerk.name] ?? "No description recorded yet."}
          </p>

          {hPerk.byRank.length > 0 && (
            <p className="mt-2 text-xs text-gray-300">
              By rank:{" "}
              {hPerk.byRank.map((value, i) => (
                <span key={i} className={i + 1 === hRank ? "font-bold text-white" : ""}>
                  {i > 0 ? " · " : ""}
                  {value}
                </span>
              ))}
            </p>
          )}

          {hPerk.gate > 0 && (
            <p
              className={`mt-3 text-sm ${hOthers >= hPerk.gate ? "text-gray-400" : "text-red-500"}`}
            >
              Requires {hPerk.gate} {hTree.name} points
            </p>
          )}
          {hReq && (
            <p
              className={`text-sm ${
                legacyRank(ranks, hTree, hReq) >= hReq.max ? "text-gray-400" : "text-red-500"
              }`}
            >
              Requires {hReq.name} at max rank
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