import Link from "next/link";
import { supabase } from "../../lib/supabase";
import { RACE_FACTION } from "../../lib/options";
import { RACE_ICONS, classIcon } from "../../lib/icons";
import { loadSpecIcons } from "../../lib/server-data";
import { loadBadgeIconOverrides, type BadgeIconOverrides } from "../../lib/badgeIconOverrides";
import type { AccountAchievementKind } from "../../lib/accountAchievements";
import AuthStatus from "../AuthStatus";
import GameIcon from "../GameIcon";
import AccountBadges from "../AccountBadges";
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
  user_id: string | null;
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
  // Plain-language explanation of what this board actually ranks by, shown
  // under the tabs - every board scores the same way (1 point per character
  // it beats, ties broken by later keys), so what varies between
  // categories isn't the "value" of a point, it's how much room there is
  // to separate from everyone else. This is what tells someone whether
  // grinding a category is actually worth it.
  description: string;
};

const boards: Record<string, Board> = {
  level: {
    label: "Level",
    keys: ["level"],
    show: (c) => c.level.toLocaleString(),
    description: "Ranked by character level - every level higher than another character earns you a point over them. Once everyone's at the cap, this board flattens out and stops being worth chasing.",
  },
  pvp: {
    label: "PvP",
    keys: ["pvp_rank", "honor_points"],
    show: (c) => `Rank ${c.pvp_rank} · ${c.honor_points.toLocaleString()} honor`,
    description: "Ranked by PvP rank first, then by Honor points to break a tie between characters at the same rank.",
  },
  gold: {
    label: "Gold",
    keys: ["money_copper"],
    show: (c) => <MoneyDisplay copper={c.money_copper} />,
    description: "Ranked by how much gold you're currently holding.",
  },
  professions: {
    label: "Professions",
    keys: ["professions_maxed"],
    show: (c) => `${c.professions_maxed}/${MAX_PROFESSIONS} maxed`,
    description: `Ranked by how many professions you've maxed out, out of ${MAX_PROFESSIONS} possible (2 primary + 3 secondary). Most people can eventually max most of these, so this board narrows fast - it's easy points early, not so much once everyone catches up.`,
  },
  legacy: {
    label: "Legacy",
    keys: ["legacy_points_spent"],
    show: (c) => `${c.legacy_points_spent.toLocaleString()} spent`,
    description: "Ranked by how many Legacy points you've spent.",
  },
};

// Negative means a is ahead of b. Later keys only break ties.
function compare<T>(a: T, b: T, keys: (keyof T)[]) {
  for (const k of keys) {
    const av = a[k] as unknown as number;
    const bv = b[k] as unknown as number;
    if (av !== bv) return bv - av;
  }
  return 0;
}

// Per-account aggregates, summed across every character the account owns -
// this is what makes leveling or gearing more alts keep paying off even
// after any one character is capped, unlike the per-character boards above.
type AccountNumKey =
  | "total_level"
  | "total_profession_skill"
  | "total_honor"
  | "total_gold"
  | "total_legacy";

type Account = {
  user_id: string;
  display_name: string;
  character_count: number;
} & Record<AccountNumKey, number>;

type AccountBoard = {
  label: string;
  keys: AccountNumKey[];
  show: (a: Account) => React.ReactNode;
  description: string;
};

const accountBoards: Record<string, AccountBoard> = {
  levels: {
    label: "Levels",
    keys: ["total_level"],
    show: (a) => a.total_level.toLocaleString(),
    description: "Ranked by the sum of every character's level on the account - leveling or rerolling more characters keeps adding to this even after your main is already capped.",
  },
  professions: {
    label: "Professions",
    keys: ["total_profession_skill"],
    show: (a) => a.total_profession_skill.toLocaleString(),
    description: `Ranked by total profession skill added up across every character and profession on the account (each profession caps at ${MAX_SKILL}) - leveling professions on alts keeps this climbing long after any single character is maxed out.`,
  },
  honor: {
    label: "Honor",
    keys: ["total_honor"],
    show: (a) => a.total_honor.toLocaleString(),
    description: "Ranked by total Honor points added up across every character on the account.",
  },
  gold: {
    label: "Gold",
    keys: ["total_gold"],
    show: (a) => <MoneyDisplay copper={a.total_gold} />,
    description: "Ranked by total gold held across every character on the account.",
  },
  legacy: {
    label: "Legacy",
    keys: ["total_legacy"],
    show: (a) => `${a.total_legacy.toLocaleString()} spent`,
    description: "Ranked by total Legacy points spent added up across every character on the account.",
  },
};

export default async function Leaderboards({
  searchParams,
}: {
  searchParams: Promise<{ sort?: string; mains?: string; view?: string }>;
}) {
  const { sort, mains, view: viewParam } = await searchParams;
  const view: "character" | "account" = viewParam === "account" ? "account" : "character";

  const key: string =
    sort && (sort === "total" || Object.keys(boards).includes(sort))
      ? sort
      : "total";
  const acctKey: string =
    sort && (sort === "total" || Object.keys(accountBoards).includes(sort))
      ? sort
      : "total";
  const mainsOnly = view === "character" && mains === "1";

  // These four requests don't depend on each other, so they're fired off
  // together with Promise.all rather than one at a time - the same fix as
  // the character page and Dashboard. Sequentially, each await waits on its
  // own round-trip before the next one starts; run together, the wait is
  // roughly whichever single one is slowest, not the sum of all four.
  const [
    { data, error },
    specIcons,
    { data: accountAchievementRows },
    iconOverrides,
  ] = await Promise.all([
    supabase
      .from("characters")
      .select("*, profiles(display_name), character_professions(skill)")
      .limit(500),
    loadSpecIcons(),
    // Account-wide badges live on the user, not any one character, so
    // they're fetched once here and matched up by user_id per row below -
    // the same approach as the Friends page. A character can show up
    // multiple times (once per character a player has), so the same
    // player's badges will repeat next to each of their entries - that's
    // expected, not a bug.
    supabase.from("account_achievements").select("user_id, kind"),
    loadBadgeIconOverrides(supabase) as Promise<BadgeIconOverrides>,
  ]);

  const rows = (data ?? []) as Row[];
  const accountAchievementsByUser: Record<string, AccountAchievementKind[]> = {};
  for (const row of (accountAchievementRows ?? []) as { user_id: string; kind: AccountAchievementKind }[]) {
    const list = accountAchievementsByUser[row.user_id] ?? [];
    list.push(row.kind);
    accountAchievementsByUser[row.user_id] = list;
  }

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
  // only how it stacks up against other mains. This only makes sense for
  // the per-character boards - the account boards are about everything an
  // account has, alts included, so they always use every character.
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

  const sortedCharacters = [...characters]
    .sort((a, b) => {
      const diff =
        key === "total"
          ? totals[b.id] - totals[a.id]
          : compare(a, b, boards[key].keys);
      return diff !== 0 ? diff : a.name.localeCompare(b.name);
    })
    .slice(0, 50);

  // Roll every character up onto its owning account. Always built from
  // every character regardless of "Mains only", since the whole point of
  // these boards is to reward the full roster, alts and all.
  const accountMap: Record<string, Account> = {};
  for (const r of rows) {
    const uid = r.user_id;
    if (!uid) continue; // characters without an owner can't be attributed to an account
    if (!accountMap[uid]) {
      accountMap[uid] = {
        user_id: uid,
        display_name: r.profiles?.display_name ?? "Unknown",
        character_count: 0,
        total_level: 0,
        total_profession_skill: 0,
        total_honor: 0,
        total_gold: 0,
        total_legacy: 0,
      };
    }
    const acc = accountMap[uid];
    acc.character_count += 1;
    acc.total_level += r.level;
    acc.total_profession_skill += r.character_professions.reduce((s, p) => s + p.skill, 0);
    acc.total_honor += r.honor_points;
    acc.total_gold += r.money_copper;
    acc.total_legacy += r.legacy_points_spent;
  }
  const accounts = Object.values(accountMap);

  const accountPoints: Record<string, Record<string, number>> = {};
  for (const [boardKey, board] of Object.entries(accountBoards)) {
    accountPoints[boardKey] = {};
    for (const a of accounts) {
      accountPoints[boardKey][a.user_id] = accounts.filter(
        (other) => compare(a, other, board.keys) < 0
      ).length;
    }
  }

  const accountTotals: Record<string, number> = {};
  for (const a of accounts) {
    accountTotals[a.user_id] = Object.keys(accountBoards).reduce(
      (sum, boardKey) => sum + accountPoints[boardKey][a.user_id],
      0
    );
  }

  const sortedAccounts = [...accounts]
    .sort((a, b) => {
      const diff =
        acctKey === "total"
          ? accountTotals[b.user_id] - accountTotals[a.user_id]
          : compare(a, b, accountBoards[acctKey].keys);
      return diff !== 0 ? diff : a.display_name.localeCompare(b.display_name);
    })
    .slice(0, 50);

  const tabs: [string, string][] = [
    ["total", "Total"],
    ...Object.entries(boards).map(([k, b]) => [k, b.label] as [string, string]),
  ];
  const accountTabs: [string, string][] = [
    ["total", "Total"],
    ...Object.entries(accountBoards).map(([k, b]) => [k, b.label] as [string, string]),
  ];

  return (
      <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <AuthStatus />
      <h1 className="text-3xl font-bold">Leaderboards</h1>

      <div className="mt-4 flex flex-wrap gap-2">
        <Link
          href="/leaderboards?view=character"
          className={`nav-btn ${view === "character" ? "nav-btn-active" : ""}`}
        >
          By character
        </Link>
        <Link
          href="/leaderboards?view=account"
          className={`nav-btn ${view === "account" ? "nav-btn-active" : ""}`}
        >
          By account
        </Link>
      </div>
      <p className="mt-2 max-w-xl text-sm text-gray-400">
        {view === "character"
          ? "Compares individual characters against each other."
          : "Compares players against each other by adding up a stat across every character they own - a strong alt army counts for just as much as one strong main."}
      </p>

      {view === "character" ? (
        <>
          <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
            <nav className="flex flex-wrap gap-2">
              {tabs.map(([k, label]) => (
                <Link
                  key={k}
                  href={`/leaderboards?view=character&sort=${k}${mainsOnly ? "&mains=1" : ""}`}
                  className={`nav-btn ${k === key ? "nav-btn-active" : ""}`}
                >
                  {label}
                </Link>
              ))}
            </nav>

            <Link
              href={`/leaderboards?view=character&sort=${key}${mainsOnly ? "" : "&mains=1"}`}
              aria-pressed={mainsOnly}
              className={`nav-btn ${mainsOnly ? "nav-btn-active" : ""}`}
            >
              {mainsOnly ? "✓ Mains only" : "Mains only"}
            </Link>
          </div>

          <p className="mt-4 max-w-xl text-sm text-gray-400">
            {key === "total" ? (
              <>
                Each board gives a character one point for every character it beats. Total adds them
                all up - a point is worth exactly the same no matter which board it came from, so what
                makes one category more worth grinding than another is how much room there still is to
                pull ahead of everyone else in it, not the category itself.
              </>
            ) : (
              <>
                {boards[key].description} Beating another character here is worth 1 point toward their
                Total score.
              </>
            )}
            {mainsOnly && " Only characters marked as a Main are being compared."}
          </p>

          {error && (
            <p className="mt-4 text-red-400">Could not load characters: {error.message}</p>
          )}

          {characters.length === 0 && !error && (
            <p className="mt-6 text-gray-400">
              {mainsOnly ? "No mains yet." : "No characters yet."}
            </p>
          )}

            <ol className="mt-6 grid items-stretch gap-3 xl:grid-cols-2">
            {sortedCharacters.map((c, i) => {
              const faction = RACE_FACTION[c.race];
              const ownerBadges = accountAchievementsByUser[c.user_id ?? ""] ?? [];
              return (
                <li key={c.id} className="h-full">
                  <Link
                    href={`/character/${c.id}`}
                    className={`lb-row h-full ${i < 3 ? `lb-row-${i + 1}` : ""}`}
                  >
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

                      {/* On its own line, same reasoning as the Friends page fix -
                          a growing row of account badges should never crowd out
                          the name or the other meta info above it. */}
                      {ownerBadges.length > 0 && (
                        <div className="mt-1.5 flex flex-wrap gap-1">
                          <AccountBadges kinds={ownerBadges} iconOverrides={iconOverrides} />
                        </div>
                      )}

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
                        <div className="mt-2">
                          <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                            Score breakdown
                          </div>
                          <div className="mt-1 flex flex-wrap gap-1.5">
                            {Object.entries(boards).map(([boardKey, b]) => (
                              <span
                                key={boardKey}
                                className="rounded bg-neutral-700 px-1.5 py-0.5 text-xs text-gray-300"
                                title={`${b.label} points`}
                              >
                                {b.label} <span className="font-bold text-amber-400">{points[boardKey][c.id]}</span>
                              </span>
                            ))}
                          </div>
                        </div>
                      )}
                    </div>

                    {key === "total" ? (
                      <div className="group/tt relative inline-flex cursor-help items-center gap-1">
                        <div className="score">{totals[c.id]} pts</div>
                        <svg
                          viewBox="0 0 20 20"
                          width="14"
                          height="14"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="1.5"
                          className="shrink-0 text-gray-500 group-hover/tt:text-amber-400"
                          aria-hidden="true"
                        >
                          <circle cx="10" cy="10" r="8.25" />
                          <path d="M10 9v5" strokeLinecap="round" />
                          <circle cx="10" cy="6.3" r="0.9" fill="currentColor" stroke="none" />
                        </svg>

                        {/* Pure-CSS tooltip (no client JS needed) - hidden until
                            the group above is hovered. Positioned above and
                            right-aligned so it never runs off the row's right
                            edge, which is where the score sits. */}
                        <div
                          className="pointer-events-none absolute bottom-full right-0 z-10 mb-2 hidden w-48 rounded-lg border border-neutral-700 bg-neutral-900 p-3 text-left shadow-lg group-hover/tt:block"
                        >
                          <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                            Score breakdown
                          </div>
                          <div className="mt-1.5 flex flex-col gap-1">
                            {Object.entries(boards).map(([boardKey, b]) => (
                              <div key={boardKey} className="flex items-center justify-between gap-3 text-sm">
                                <span className="text-gray-300">{b.label}</span>
                                <span className="font-bold text-amber-400">{points[boardKey][c.id]}</span>
                              </div>
                            ))}
                          </div>
                          {/* Little downward-pointing arrow so the box visibly
                              connects to the score it belongs to. */}
                          <div className="absolute -bottom-1 right-3 h-2 w-2 rotate-45 border-b border-r border-neutral-700 bg-neutral-900" />
                        </div>
                      </div>
                    ) : (
                      <div className="score">{boards[key].show(c)}</div>
                    )}
                  </Link>
                </li>
              );
            })}
          </ol>
        </>
      ) : (
        <>
          <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
            <nav className="flex flex-wrap gap-2">
              {accountTabs.map(([k, label]) => (
                <Link
                  key={k}
                  href={`/leaderboards?view=account&sort=${k}`}
                  className={`nav-btn ${k === acctKey ? "nav-btn-active" : ""}`}
                >
                  {label}
                </Link>
              ))}
            </nav>
          </div>

          <p className="mt-4 max-w-xl text-sm text-gray-400">
            {acctKey === "total" ? (
              <>
                Each board gives an account one point for every account it beats. Total adds them all
                up the same way the per-character Total does - every character on the account counts,
                so more alts, more professions leveled and more gold banked all keep adding up even
                after any one character has nothing left to grind.
              </>
            ) : (
              <>
                {accountBoards[acctKey].description} Beating another account here is worth 1 point
                toward their Total score.
              </>
            )}
          </p>

          {error && (
            <p className="mt-4 text-red-400">Could not load characters: {error.message}</p>
          )}

          {accounts.length === 0 && !error && (
            <p className="mt-6 text-gray-400">No accounts yet.</p>
          )}

          <ol className="mt-6 grid items-stretch gap-3 xl:grid-cols-2">
            {sortedAccounts.map((a, i) => {
              const ownerBadges = accountAchievementsByUser[a.user_id] ?? [];
              return (
                <li key={a.user_id} className="h-full">
                  <div className={`lb-row h-full ${i < 3 ? `lb-row-${i + 1}` : ""}`}>
                    <span className={`rank-badge ${i < 3 ? `rank-${i + 1}` : ""}`}>{i + 1}</span>

                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-lg font-bold text-white">{a.display_name}</span>
                        <span className="rounded bg-neutral-600 px-2 py-0.5 text-xs">
                          {a.character_count} {a.character_count === 1 ? "character" : "characters"}
                        </span>
                      </div>

                      {ownerBadges.length > 0 && (
                        <div className="mt-1.5 flex flex-wrap gap-1">
                          <AccountBadges kinds={ownerBadges} iconOverrides={iconOverrides} />
                        </div>
                      )}

                      {acctKey === "total" && (
                        <div className="mt-2">
                          <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                            Score breakdown
                          </div>
                          <div className="mt-1 flex flex-wrap gap-1.5">
                            {Object.entries(accountBoards).map(([boardKey, b]) => (
                              <span
                                key={boardKey}
                                className="rounded bg-neutral-700 px-1.5 py-0.5 text-xs text-gray-300"
                                title={`${b.label} points`}
                              >
                                {b.label}{" "}
                                <span className="font-bold text-amber-400">
                                  {accountPoints[boardKey][a.user_id]}
                                </span>
                              </span>
                            ))}
                          </div>
                        </div>
                      )}
                    </div>

                    {acctKey === "total" ? (
                      <div className="group/tt relative inline-flex cursor-help items-center gap-1">
                        <div className="score">{accountTotals[a.user_id]} pts</div>
                        <svg
                          viewBox="0 0 20 20"
                          width="14"
                          height="14"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="1.5"
                          className="shrink-0 text-gray-500 group-hover/tt:text-amber-400"
                          aria-hidden="true"
                        >
                          <circle cx="10" cy="10" r="8.25" />
                          <path d="M10 9v5" strokeLinecap="round" />
                          <circle cx="10" cy="6.3" r="0.9" fill="currentColor" stroke="none" />
                        </svg>

                        <div className="pointer-events-none absolute bottom-full right-0 z-10 mb-2 hidden w-48 rounded-lg border border-neutral-700 bg-neutral-900 p-3 text-left shadow-lg group-hover/tt:block">
                          <div className="text-[10px] font-semibold uppercase tracking-wide text-gray-500">
                            Score breakdown
                          </div>
                          <div className="mt-1.5 flex flex-col gap-1">
                            {Object.entries(accountBoards).map(([boardKey, b]) => (
                              <div key={boardKey} className="flex items-center justify-between gap-3 text-sm">
                                <span className="text-gray-300">{b.label}</span>
                                <span className="font-bold text-amber-400">
                                  {accountPoints[boardKey][a.user_id]}
                                </span>
                              </div>
                            ))}
                          </div>
                          <div className="absolute -bottom-1 right-3 h-2 w-2 rotate-45 border-b border-r border-neutral-700 bg-neutral-900" />
                        </div>
                      </div>
                    ) : (
                      <div className="score">{accountBoards[acctKey].show(a)}</div>
                    )}
                  </div>
                </li>
              );
            })}
          </ol>
        </>
      )}
    </main>
  );
}