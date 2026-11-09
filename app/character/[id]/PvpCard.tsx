// PvP summary (2026-11-05). Honor and kill counts come from the addon's
// PvP export (1.9.2+) when the client answers those APIs, otherwise from
// the game's own Statistics pane rows, which every addon version sends.

export type PvpData = {
  honor?: number;
  honorMax?: number;
  lifetimeHonorableKills?: number;
  lifetimeDishonorableKills?: number;
  todayHonorableKills?: number;
  honorTracked?: number;
} | null;

type StatRow = { category: string; name: string; value: string };

function statNumber(stats: StatRow[], name: string): number | null {
  const row = stats.find((s) => s.name === name);
  if (!row) return null;
  const n = Number(row.value.replace(/,/g, ""));
  return Number.isFinite(n) ? n : null;
}

function firstNumber(...values: (number | null | undefined)[]): number | null {
  for (const v of values) if (typeof v === "number" && Number.isFinite(v)) return v;
  return null;
}

export default function PvpCard({
  honor,
  rank,
  pvp,
  stats,
}: {
  honor: number | null;
  rank: number | null;
  pvp: PvpData;
  stats: StatRow[];
}) {
  const honorableKills = firstNumber(
    statNumber(stats, "Total Honorable Kills"),
    pvp?.lifetimeHonorableKills
  );
  const rows: { label: string; value: string }[] = [];
  const add = (label: string, value: number | null) => {
    if (value !== null) rows.push({ label, value: value.toLocaleString() });
  };

  // The game's honor value can read 0 while you're earning honor, so the
  // addon's own tally (1.9.10+) replaces a 0 bar
  const tracked = firstNumber(pvp?.honorTracked);
  const honorNow = firstNumber(pvp?.honor, honor);
  if (tracked !== null && tracked > 0 && !honorNow) {
    add("Honor earned", tracked);
  } else if (honorNow !== null) {
    rows.push({
      label: "Honor",
      value: pvp?.honorMax ? `${honorNow.toLocaleString()} / ${pvp.honorMax.toLocaleString()}` : honorNow.toLocaleString(),
    });
  }
  add("PvP rank", rank);
  add("Honorable kills", honorableKills);
  add("Honorable kills today", firstNumber(pvp?.todayHonorableKills));
  add("Dishonorable kills", firstNumber(pvp?.lifetimeDishonorableKills));
  add("Killing blows", statNumber(stats, "Total Killing Blows"));
  add("World honorable kills", statNumber(stats, "World Honorable Kills"));
  add("Battleground honorable kills", statNumber(stats, "Battleground Honorable Kills"));
  add("Battlegrounds played", statNumber(stats, "Battlegrounds played"));
  add("Battlegrounds won", statNumber(stats, "Battlegrounds won"));
  add("Deaths from other players", statNumber(stats, "Total deaths from other players"));

  return (
    <section className="rounded bg-neutral-800 p-4">
      <h2 className="font-bold">PvP</h2>
      {rows.length === 0 ? (
        <p className="mt-2 text-sm text-gray-400">No PvP recorded yet.</p>
      ) : (
        <dl className="mt-2 grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
          {rows.map((r) => (
            <div key={r.label} className="contents">
              <dt className="text-gray-400">{r.label}</dt>
              <dd className="text-right font-semibold text-white">{r.value}</dd>
            </div>
          ))}
        </dl>
      )}
    </section>
  );
}
