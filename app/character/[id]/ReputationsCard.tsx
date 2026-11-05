// Reputation standings (2026-11-05, addon 1.9.2+), grouped the way the
// in-game Reputation pane groups them.

export type ReputationRow = {
  name: string;
  header: string | null;
  standing: number;
  standing_label: string | null;
  value: number;
  max: number;
};

const STANDING_LABELS = ["", "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted"];

// Bar colours follow the game's standing colours
const STANDING_COLORS = [
  "",
  "bg-red-700",
  "bg-red-600",
  "bg-orange-600",
  "bg-yellow-500",
  "bg-green-600",
  "bg-green-500",
  "bg-emerald-400",
  "bg-cyan-400",
];

export default function ReputationsCard({ reputations }: { reputations: ReputationRow[] }) {
  if (reputations.length === 0) {
    return (
      <section className="rounded bg-neutral-800 p-4">
        <h2 className="font-bold">Reputation</h2>
        <p className="mt-2 text-sm text-gray-400">
          No reputations yet - sync with addon 1.9.2 or newer.
        </p>
      </section>
    );
  }

  const groups = new Map<string, ReputationRow[]>();
  for (const rep of reputations) {
    const key = rep.header ?? "Other";
    const list = groups.get(key) ?? [];
    list.push(rep);
    groups.set(key, list);
  }

  return (
    <section className="rounded bg-neutral-800 p-4">
      <h2 className="font-bold">Reputation</h2>
      <div className="mt-2 flex flex-col gap-3">
        {[...groups.entries()].map(([header, reps]) => (
          <div key={header}>
            <h3 className="text-xs uppercase tracking-wide text-gray-400">{header}</h3>
            <ul className="mt-1 flex flex-col gap-1.5">
              {reps
                .slice()
                .sort((a, b) => b.standing - a.standing || b.value - a.value)
                .map((rep) => {
                  const label = rep.standing_label ?? STANDING_LABELS[rep.standing] ?? `Standing ${rep.standing}`;
                  const pct = rep.max > 0 ? Math.min(100, (rep.value / rep.max) * 100) : 100;
                  return (
                    <li key={rep.name} className="text-sm">
                      <div className="flex justify-between gap-2">
                        <span className="truncate text-white">{rep.name}</span>
                        <span className="shrink-0 text-gray-400">
                          {label}
                          {rep.max > 0 && ` ${rep.value.toLocaleString()}/${rep.max.toLocaleString()}`}
                        </span>
                      </div>
                      <div className="mt-0.5 h-1.5 overflow-hidden rounded bg-neutral-900">
                        <div
                          className={`h-full ${STANDING_COLORS[rep.standing] ?? "bg-gray-500"}`}
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                    </li>
                  );
                })}
            </ul>
          </div>
        ))}
      </div>
    </section>
  );
}
