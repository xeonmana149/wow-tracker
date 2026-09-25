import Link from "next/link";
import type { Leaderboard } from "../lib/leaderboards";

const MEDALS = ["🥇", "🥈", "🥉"];

// Dashboard-level leaderboards, built from the same Statistics pane data
// the character page's Statistics section and the new tiered badges use
// (2026-09-25 rework). Server component - takes already-fetched data, same
// pattern as the rest of the dashboard.
export default function LeaderboardsCard({ leaderboards }: { leaderboards: Leaderboard[] }) {
  if (leaderboards.length === 0) {
    return null;
  }

  return (
    <section className="rounded bg-neutral-800 p-4">
      <h2 className="font-bold">Leaderboards</h2>
      <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {leaderboards.map((board) => (
          <div key={board.key} className="rounded border border-neutral-700 bg-neutral-900/40 p-3">
            <p className="text-sm font-semibold text-gray-200">{board.label}</p>
            <ol className="mt-2 flex flex-col gap-1">
              {board.entries.map((entry, i) => (
                <li key={entry.characterId} className="flex items-center justify-between gap-3 text-sm">
                  <span className="flex items-center gap-1.5 text-gray-300">
                    <span className="w-5 text-center">{MEDALS[i] ?? `${i + 1}.`}</span>
                    <Link href={`/character/${entry.characterId}`} className="hover:underline">
                      {entry.characterName}
                    </Link>
                  </span>
                  <span className="font-semibold text-[#c9a566]">{entry.value.toLocaleString()}</span>
                </li>
              ))}
            </ol>
          </div>
        ))}
      </div>
    </section>
  );
}