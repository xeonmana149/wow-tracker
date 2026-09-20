import Link from "next/link";
import { supabase } from "../../lib/supabase";
import { RACE_FACTION } from "../../lib/options";
import { RACE_ICONS, classIcon } from "../../lib/icons";
import { loadSpecIcons } from "../../lib/server-data";
import AuthStatus from "../AuthStatus";
import GameIcon from "../GameIcon";
import { MoneyDisplay } from "../MoneyIcons";

export const dynamic = "force-dynamic";

const MAX_SKILL = 300;
const MAX_PROFESSIONS = 5; // 2 primary + 3 secondary

type NumKey =
  | "level"
  | "pvp_rank"
  | "honor_points"
  | "money_copper"
  | "professions_maxed"
  | "legacy_points_spent";

// These are worked out from other tables, not stored on the character
type Computed = "professions_maxed";

type Info = {
  id: string;
  name: string;
  race: string;
  class: string;
  character_type: string;
  ruleset: string | null;
  main_spec: string | null;
  profiles: { display_name: string } | null;
};

type Character = Info & Record<NumKey, number>;

// What the database sends back
type Row = Info & {
  character_professions: { skill: number }[];
} & Record<Exclude<NumKey, Computed>, number>;

type Board = {
  label: string;
  keys: NumKey[];
  show: (c: Character) => React.ReactNode;
};

const boards: Record<string, Board> = {
  level: {
    label: "Level",
    keys: ["level"],
    show: (c) => c.level.toLocaleString(),
  },
  pvp: {
    label: "PvP",
    keys: ["pvp_rank", "honor_points"],
    show: (c) => `Rank ${c.pvp_rank} · ${c.honor_points.toLocaleString()} honor`,
  },
  gold: {
    label: "Gold",
    keys: ["money_copper"],
    show: (c) => <MoneyDisplay copper={c.money_copper} />,
  },
  professions: {
    label: "Professions",
    keys: ["professions_maxed"],
    show: (c) => `${c.professions_maxed}/${MAX_PROFESSIONS} maxed`,
  },
  legacy: {
    label: "Legacy",
    keys: ["legacy_points_spent"],
    show: (c) => `${c.legacy_points_spent.toLocaleString()} spent`,
  },
};

// Negative means a is ahead of b. Later keys only break ties.
function compare(a: Character, b: Character, keys: NumKey[]) {
  for (const k of keys) {
    if (a[k] !== b[k]) return b[k] - a[k];
  }
  return 0;
}

export default async function Leaderboards({
  searchParams,
}: {
  searchParams: Promise<{ sort?: string; mains?: string }>;
}) {
  const { sort, mains } = await searchParams;
  const key: string =
    sort && (sort === "total" || Object.keys(boards).includes(sort))
      ? sort
      : "total";
  const mainsOnly = mains === "1";

  const { data, error } = await supabase
    .from("characters")
    .select("*, profiles(display_name), character_professions(skill)")
    .limit(500);

  const specIcons = await loadSpecIcons();
  const rows = (data ?? []) as Row[];

  const allCharacters: Character[] = rows.map((r) => {
    return {
      ...r,
      professions_maxed: r.character_professions.filter((p) => p.skill >= MAX_SKILL)
        .length,
    };
  });

  // "Mains only" compares just each player's main against other mains,
  // rather than every alt/gatherer/PvPer character too - filtered before
  // any of the points/ranking math below runs, so a main's rank reflects
  // only how it stacks up against other mains.
  const characters = mainsOnly
    ? allCharacters.filter((c) => c.character_type === "Main")
    : allCharacters;

  // points[board][character id] = how many characters this one beats
  const points: Record<string, Record<string, number>> = {};
  for (const [boardKey, board] of Object.entries(boards)) {
    points[boardKey] = {};
    for (const c of characters) {
      points[boardKey][c.id] = characters.filter(
        (other) => compare(c, other, board.keys) < 0
      ).length;
    }
  }

  const totals: Record<string, number> = {};
  for (const c of characters) {
    totals[c.id] = Object.keys(boards).reduce(
      (sum, boardKey) => sum + points[boardKey][c.id],
      0
    );
  }

  const sorted = [...characters]
    .sort((a, b) => {
      const diff =
        key === "total"
          ? totals[b.id] - totals[a.id]
          : compare(a, b, boards[key].keys);
      return diff !== 0 ? diff : a.name.localeCompare(b.name);
    })
    .slice(0, 50);

  const tabs: [string, string][] = [
    ["total", "Total"],
    ...Object.entries(boards).map(([k, b]) => [k, b.label] as [string, string]),
  ];

  return (
      <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <AuthStatus />
      <h1 className="text-3xl font-bold">Leaderboards</h1>

      <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
        <nav className="flex flex-wrap gap-2">
          {tabs.map(([k, label]) => (
            <Link
              key={k}
              href={`/leaderboards?sort=${k}${mainsOnly ? "&mains=1" : ""}`}
              className={`nav-btn ${k === key ? "nav-btn-active" : ""}`}
            >
              {label}
            </Link>
          ))}
        </nav>

        <Link
          href={`/leaderboards?sort=${key}${mainsOnly ? "" : "&mains=1"}`}
          aria-pressed={mainsOnly}
          className={`nav-btn ${mainsOnly ? "nav-btn-active" : ""}`}
        >
          {mainsOnly ? "✓ Mains only" : "Mains only"}
        </Link>
      </div>

      {key === "total" && (
        <p className="mt-4 max-w-xl text-sm text-gray-400">
          Each board gives a character one point for every character it beats.
          Total adds them all up.
          {mainsOnly && " Only characters marked as a Main are being compared."}
        </p>
      )}

      {error && (
        <p className="mt-4 text-red-400">Could not load characters: {error.message}</p>
      )}

      {characters.length === 0 && !error && (
        <p className="mt-6 text-gray-400">
          {mainsOnly ? "No mains yet." : "No characters yet."}
        </p>
      )}

        <ol className="mt-6 grid gap-3 xl:grid-cols-2">
        {sorted.map((c, i) => {
          const faction = RACE_FACTION[c.race];
          return (
            <li key={c.id}>
              <Link href={`/character/${c.id}`} className="lb-row">
                <span className={`rank-badge ${i < 3 ? `rank-${i + 1}` : ""}`}>{i + 1}</span>

                <GameIcon name={classIcon(c.class)} label={c.class} size={48} round />

                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-lg font-bold text-white">{c.name}</span>
                    <span className="rounded bg-neutral-600 px-2 py-0.5 text-xs">
                      {c.character_type}
                    </span>
                  </div>

                  <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-gray-400">
                    <span className="flex items-center gap-1.5">
                      <GameIcon name={RACE_ICONS[c.race]} label={c.race} size={18} round />
                      Level {c.level} {c.race} {c.class}
                    </span>
                    {c.main_spec && (
                      <span className="flex items-center gap-1.5">
                        <GameIcon
                          name={specIcons[`${c.class}|${c.main_spec}`]}
                          label={c.main_spec}
                          size={18}
                        />
                        {c.main_spec}
                      </span>
                    )}
                    <span>{c.profiles?.display_name ?? "Unknown"}</span>
                  </div>

                  <div className="mt-2 flex flex-wrap gap-2">
                    {faction && (
                      <span
                        className={`chip ${
                          faction === "Alliance" ? "chip-alliance" : "chip-horde"
                        }`}
                      >
                        {faction}
                      </span>
                    )}
                    {c.ruleset && <span className="chip">{c.ruleset}</span>}
                  </div>

                  {key === "total" && (
                    <div className="mt-2 text-xs text-gray-600">
                      {Object.entries(boards)
                        .map(([boardKey, b]) => `${b.label} ${points[boardKey][c.id]}`)
                        .join(" · ")}
                    </div>
                  )}
                </div>

                <div className="score">
                  {key === "total" ? `${totals[c.id]} pts` : boards[key].show(c)}
                </div>
              </Link>
            </li>
          );
        })}
      </ol>
    </main>
  );
}