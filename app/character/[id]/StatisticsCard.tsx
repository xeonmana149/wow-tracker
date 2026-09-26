"use client";

import { useMemo, useState } from "react";

export type StatisticRow = {
  category: string;
  name: string;
  value: string;
};

function isTracked(value: string) {
  return value.trim() !== "" && value.trim() !== "--";
}

// Blizzard's own Statistics UI formats money stats (e.g. "Total gold
// acquired", "Most gold ever owned") using in-game texture escape codes -
// something like "1|TInterface\MoneyFrame\UI-GoldIcon:0:0:2:0|t56|T...
// SilverIcon...|t12|T...CopperIcon...|t". The WoW client renders |T...|t as
// a little coin icon; outside the game it's just meaningless text, and the
// addon exports GetStatistic()'s value verbatim since it has no way to know
// this site can't render WoW's texture syntax. Detected and reformatted
// here instead of changing what the addon exports (every existing synced
// row already has this raw text baked in, so this has to be tolerant on
// read regardless of what future addon versions do).
const MONEY_ICON_RE = /(\d+)\s*\|T[^|]*?(Gold|Silver|Copper)Icon[^|]*\|t/gi;

function parseBlizzardMoneyString(value: string): number | null {
  MONEY_ICON_RE.lastIndex = 0;
  let match: RegExpExecArray | null;
  let gold = 0,
    silver = 0,
    copper = 0,
    found = false;
  while ((match = MONEY_ICON_RE.exec(value))) {
    found = true;
    const amount = Number(match[1]);
    const kind = match[2].toLowerCase();
    if (kind === "gold") gold = amount;
    else if (kind === "silver") silver = amount;
    else if (kind === "copper") copper = amount;
  }
  return found ? gold * 10000 + silver * 100 + copper : null;
}

// Renders a stat's value, transparently reformatting Blizzard's raw money
// texture-strings into plain "Xg Ys Zc" text with WoW's usual coin colors -
// everything else (most stats are plain numbers or names) passes through
// unchanged.
function StatValue({ value, className }: { value: string; className?: string }) {
  const copper = parseBlizzardMoneyString(value);
  if (copper === null) return <span className={className}>{value}</span>;

  const gold = Math.floor(copper / 10000);
  const silver = Math.floor((copper % 10000) / 100);
  const bronze = copper % 100;
  return (
    <span className={className}>
      {gold > 0 && <span style={{ color: "#ffd700" }}>{gold.toLocaleString()}g </span>}
      {(silver > 0 || gold > 0) && <span style={{ color: "#c0c0c0" }}>{silver}s </span>}
      <span style={{ color: "#b87333" }}>{bronze}c</span>
    </span>
  );
}

// "1,502" -> 1502. NaN for anything that isn't a plain number (e.g.
// "Warsong Gulch" for a "Battleground played the most" stat) - those just
// don't participate in magnitude-based picks below.
function parseNumber(value: string): number {
  return Number(value.replace(/,/g, ""));
}

// Phase 1 shipped this as one flat accordion per raw Blizzard category -
// technically correct, but it read like a database dump (25 categories,
// some duplicated by near-identical name, sorted alphabetically so
// "Alterac Valley battles" sat 1400px away from its own value with no
// grouping). Redesigned 2026-09-25 per feedback: group the raw categories
// into a handful of meaningful sections, show a scannable overview grid
// first, and drill into a section as a column layout instead of one long
// list. See MetaGroup below for the ~25-raw-categories -> ~7-sections
// mapping this is built on.
type MetaGroup = {
  key: string;
  label: string;
  icon: string;
  // Blizzard's own category names (as GetCategoryInfo returns them) that
  // roll up into this section. A raw category not listed under any group
  // lands in "misc" via the fallback below, so nothing silently disappears
  // if this server's category names ever shift.
  rawCategories: string[];
  // Keywords (checked against stat name, lowercased) used to pick a
  // headline number to feature for this group - first match wins, so more
  // specific/interesting stats are listed first.
  headlineKeywords: string[];
};

const META_GROUPS: MetaGroup[] = [
  {
    key: "combat",
    label: "Combat",
    icon: "⚔",
    rawCategories: ["Combat", "Killing Blows", "Kills", "Creatures"],
    headlineKeywords: ["creatures killed", "total killing blows", "total kills", "killing blows"],
  },
  {
    key: "pvp",
    label: "PvP",
    icon: "🏆",
    rawCategories: ["Battlegrounds", "Honorable Kills", "Player vs. Player"],
    headlineKeywords: ["total honorable kills", "honorable kills", "battlegrounds won", "victories"],
  },
  {
    key: "pve",
    label: "PvE",
    icon: "🏰",
    rawCategories: ["Dungeons & Raids", "Dungeons and Raids", "Boss Kills"],
    headlineKeywords: ["kills", "entered", "completed"],
  },
  {
    key: "character",
    label: "Character",
    icon: "🧝",
    rawCategories: ["Character", "Gear", "Wealth", "Reputation"],
    headlineKeywords: ["total gold acquired", "gold", "epic items acquired", "factions"],
  },
  {
    key: "progression",
    label: "Progression",
    icon: "📈",
    rawCategories: ["Quests", "Professions", "Skills", "Secondary Skills"],
    headlineKeywords: ["quests completed", "recipes known", "skill"],
  },
  {
    key: "world",
    label: "World",
    icon: "🌍",
    rawCategories: ["Travel", "World", "Social"],
    headlineKeywords: ["hearthed", "flight paths taken", "duels won"],
  },
  {
    key: "misc",
    label: "Miscellaneous",
    icon: "📦",
    rawCategories: ["Consumables", "Deaths", "Resurrection"],
    headlineKeywords: ["total deaths", "used", "consumed"],
  },
];

// A handful of well-known zone/profession names this server's stat names
// tend to be built around (e.g. "Deaths in Alterac Valley", "Blacksmithing
// Recipes learned"). Not exhaustive - anything that doesn't contain one of
// these just lands in a "General" bucket within its column, which is no
// worse than the old flat list. Longer/more specific names are listed
// first so e.g. "Darkspear Islands" is checked before a shorter partial
// name could ever conflict with it.
const KNOWN_SUBGROUPS = [
  "Darkspear Islands",
  "Darkspear Island",
  "Alterac Valley",
  "Arathi Basin",
  "Warsong Gulch",
  "Eye of the Storm",
  "Isle of Conquest",
  "Strand of the Ancients",
  "Silvershard Mines",
  "Temple of Kotmogu",
  "Deepwind Gorge",
  "Blacksmithing",
  "Leatherworking",
  "Alchemy",
  "Herbalism",
  "Mining",
  "Skinning",
  "Tailoring",
  "Engineering",
  "Enchanting",
  "Jewelcrafting",
  "Inscription",
  "First Aid",
  "Cooking",
  "Fishing",
];

function subgroupFor(name: string): string {
  for (const known of KNOWN_SUBGROUPS) {
    if (name.includes(known)) return known;
  }
  return "General";
}

function metaGroupFor(rawCategory: string): MetaGroup {
  return (
    META_GROUPS.find((g) => g.rawCategories.includes(rawCategory)) ??
    META_GROUPS[META_GROUPS.length - 1]
  );
}

function pickHeadline(
  rows: StatisticRow[],
  keywords: string[]
): { name: string; value: string } | null {
  const tracked = rows.filter((r) => isTracked(r.value));
  for (const kw of keywords) {
    const hit = tracked.find((r) => r.name.toLowerCase().includes(kw));
    if (hit) return hit;
  }
  // No keyword matched anything this character has - fall back to
  // whichever tracked stat has the largest plain-number value, so a group
  // still shows *something* interesting rather than nothing.
  let best: StatisticRow | null = null;
  let bestValue = -Infinity;
  for (const r of tracked) {
    const n = parseNumber(r.value);
    if (!Number.isNaN(n) && n > bestValue) {
      best = r;
      bestValue = n;
    }
  }
  return best ? { name: best.name, value: best.value } : null;
}

export default function StatisticsCard({ stats }: { stats: StatisticRow[] }) {
  const [hideUntouched, setHideUntouched] = useState(true);
  const [query, setQuery] = useState("");
  const [openGroup, setOpenGroup] = useState<string | null>(null);

  const trackedTotal = stats.filter((s) => isTracked(s.value)).length;

  const grouped = useMemo(() => {
    const byMeta = new Map<string, StatisticRow[]>();
    for (const s of stats) {
      const meta = metaGroupFor(s.category);
      const list = byMeta.get(meta.key) ?? [];
      list.push(s);
      byMeta.set(meta.key, list);
    }
    return byMeta;
  }, [stats]);

  const searchResults = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return null;
    return stats
      .filter((s) => s.name.toLowerCase().includes(q) || s.category.toLowerCase().includes(q))
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [stats, query]);

  if (stats.length === 0) {
    return (
      <section className="rounded bg-neutral-800 p-4">
        <h2 className="font-bold">Statistics</h2>
        <p className="mt-2 text-sm text-gray-500">
          No statistics recorded yet - sync with an addon version that reports them.
        </p>
      </section>
    );
  }

  const openMeta = openGroup ? META_GROUPS.find((g) => g.key === openGroup) : null;
  const openRows = openGroup ? grouped.get(openGroup) ?? [] : [];

  return (
    <section className="rounded bg-neutral-800 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="font-bold">Statistics</h2>
        <span className="text-xs text-gray-500">
          {trackedTotal} of {stats.length} discovered
        </span>
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-2">
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search statistics..."
          className="min-w-[180px] flex-1 rounded border border-neutral-700 bg-neutral-900 px-3 py-1.5 text-sm text-gray-200 placeholder:text-gray-500"
        />
        <label className="flex items-center gap-1.5 text-xs text-gray-400">
          <input
            type="checkbox"
            checked={hideUntouched}
            onChange={(e) => setHideUntouched(e.target.checked)}
          />
          Hide untouched
        </label>
      </div>

      {searchResults ? (
        <div className="mt-3 flex flex-col gap-1">
          {searchResults.length === 0 && (
            <p className="text-sm text-gray-500">No stats match &quot;{query}&quot;.</p>
          )}
          {searchResults.map((r) => (
            <div
              key={`${r.category}-${r.name}`}
              className="flex items-center justify-between gap-3 rounded border border-neutral-700 bg-neutral-900/40 px-3 py-1.5 text-sm"
            >
              <span className="text-gray-300">
                {r.name}
                <span className="ml-2 text-xs text-gray-500">{r.category}</span>
              </span>
              <StatValue
                value={r.value}
                className={`font-semibold ${isTracked(r.value) ? "text-[#c9a566]" : "text-gray-600"}`}
              />
            </div>
          ))}
        </div>
      ) : (
        <>
          {/* Overview: one card per meta-group, each with a tracked count
              and (when there's something worth featuring) a headline
              number, so the page says something about the character before
              anyone clicks into anything. */}
          <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3">
            {META_GROUPS.map((g) => {
              const rows = grouped.get(g.key) ?? [];
              if (rows.length === 0) return null;
              const tracked = rows.filter((r) => isTracked(r.value)).length;
              const headline = pickHeadline(rows, g.headlineKeywords);
              const isOpen = openGroup === g.key;
              return (
                <button
                  key={g.key}
                  type="button"
                  onClick={() => setOpenGroup(isOpen ? null : g.key)}
                  className={`flex flex-col items-start gap-1 rounded border p-3 text-left transition ${
                    isOpen
                      ? "border-[#c9a566] bg-neutral-900/60"
                      : "border-neutral-700 bg-neutral-900/40 hover:border-neutral-500"
                  }`}
                >
                  <span className="flex w-full items-center justify-between text-sm font-semibold">
                    <span>
                      {g.icon} {g.label}
                    </span>
                    <span className="text-xs font-normal text-gray-500">{tracked} tracked</span>
                  </span>
                  {headline ? (
                    <span className="text-lg font-bold text-[#c9a566]">
                      <StatValue value={headline.value} />
                      <span className="ml-1.5 text-xs font-normal text-gray-400">
                        {headline.name}
                      </span>
                    </span>
                  ) : (
                    <span className="text-xs text-gray-600">Nothing tracked yet</span>
                  )}
                </button>
              );
            })}
          </div>

          {/* Drill-down: the selected meta-group's raw categories laid out
              as columns (sub-grouped by zone/profession where recognized)
              instead of one giant alphabetical list. */}
          {openMeta && (
            <div className="mt-4 rounded border border-neutral-700 bg-neutral-900/30 p-3">
              <div className="flex items-center justify-between">
                <h3 className="text-sm font-bold">
                  {openMeta.icon} {openMeta.label}
                </h3>
                <button
                  type="button"
                  onClick={() => setOpenGroup(null)}
                  className="text-xs text-gray-500 hover:text-gray-300"
                >
                  Close
                </button>
              </div>
              <div className="mt-3 flex flex-wrap gap-3">
                {openMeta.rawCategories.map((rawCategory) => {
                  const rowsForCategory = openRows.filter((r) => r.category === rawCategory);
                  if (rowsForCategory.length === 0) return null;

                  const bySubgroup = new Map<string, StatisticRow[]>();
                  for (const r of rowsForCategory.filter(
                    (r) => !hideUntouched || isTracked(r.value)
                  )) {
                    const sub = subgroupFor(r.name);
                    const list = bySubgroup.get(sub) ?? [];
                    list.push(r);
                    bySubgroup.set(sub, list);
                  }
                  const subKeys = Array.from(bySubgroup.keys()).sort((a, b) => {
                    if (a === "General") return 1;
                    if (b === "General") return -1;
                    return a.localeCompare(b);
                  });
                  if (subKeys.length === 0) return null;

                  return subKeys.map((sub) => {
                    const rows = (bySubgroup.get(sub) ?? []).sort((a, b) =>
                      a.name.localeCompare(b.name)
                    );
                    return (
                      <div
                        key={`${rawCategory}-${sub}`}
                        className="min-w-[220px] flex-1 rounded border border-neutral-800 bg-neutral-900/40 p-2"
                      >
                        <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-gray-400">
                          {sub === "General" ? rawCategory : sub}
                        </p>
                        <ul className="flex flex-col gap-1 text-sm">
                          {rows.map((r) => (
                            <li key={r.name} className="flex items-center justify-between gap-3">
                              <span className="text-gray-300">{r.name}</span>
                              <StatValue
                                value={r.value}
                                className={`font-semibold ${
                                  isTracked(r.value) ? "text-[#c9a566]" : "text-gray-600"
                                }`}
                              />
                            </li>
                          ))}
                        </ul>
                      </div>
                    );
                  });
                })}
              </div>
            </div>
          )}
        </>
      )}
    </section>
  );
}