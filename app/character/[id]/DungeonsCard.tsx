// Dungeon & raid clear totals (2026-11-11, "can you add somewhere on a
// character page dungeon clears and raid clears ... like totals").
// From the game's own Statistics pane, which every sync sends:
//   - "Boss Kills": one counter per final boss, e.g. "Aku'mai kills
//     (Blackfathom Deeps)" - a place's clears are its highest counter
//     (Scarlet Monastery's Cathedral and Dalaran each have two bosses that
//     die in the same run, so adding them would count one run twice)
//   - "Dungeons and Raids": how many dungeons and raids were entered

type StatRow = { category: string; name: string; value: string };

// Everything else in Boss Kills is counted as a dungeon
const RAIDS = new Set([
  "Onyxia's Lair",
  "Molten Core",
  "Blackwing Lair",
  "Zul'Gurub",
  "Ruins of Ahn'Qiraj",
  "Temple of Ahn'Qiraj",
  "Ahn'Qiraj",
  "Naxxramas",
]);

function toNumber(value: string | null | undefined): number {
  const n = Number(String(value ?? "").replace(/,/g, ""));
  return Number.isFinite(n) ? n : 0;
}

// "Edwin VanCleef Kills (Deadmines)" -> { boss, place }
function parseBossStat(name: string): { boss: string; place: string } {
  const m = /^(.*?)\s+kills\s*(?:\((.*)\))?\s*$/i.exec(name);
  return m ? { boss: m[1], place: m[2] ?? m[1] } : { boss: name, place: name };
}

type Place = { place: string; clears: number; raid: boolean };

export default function DungeonsCard({ stats }: { stats: StatRow[] }) {
  const byPlace = new Map<string, Place>();
  for (const s of stats) {
    if (s.category !== "Boss Kills") continue;
    const { place } = parseBossStat(s.name);
    const kills = toNumber(s.value);
    const known = byPlace.get(place);
    if (!known) byPlace.set(place, { place, clears: kills, raid: RAIDS.has(place) });
    else known.clears = Math.max(known.clears, kills);
  }
  const places = [...byPlace.values()];
  const cleared = places.filter((p) => p.clears > 0).sort((a, b) => b.clears - a.clears || a.place.localeCompare(b.place));
  const dungeons = places.filter((p) => !p.raid);
  const raids = places.filter((p) => p.raid);
  const sum = (list: Place[]) => list.reduce((n, p) => n + p.clears, 0);

  const entered = (pattern: RegExp) =>
    stats
      .filter((s) => (s.category === "Dungeons and Raids" || s.category === "Dungeons & Raids") && pattern.test(s.name))
      .reduce((n, s) => n + toNumber(s.value), 0);
  const dungeonsEntered = entered(/^Total 5-player dungeons entered$/i);
  const raidsEntered = entered(/^Total \d+-player raids entered$/i);

  const tiles = [
    { label: "Dungeon clears", value: sum(dungeons), sub: `${dungeons.filter((p) => p.clears > 0).length} of ${dungeons.length} dungeons` },
    { label: "Raid clears", value: sum(raids), sub: `${raids.filter((p) => p.clears > 0).length} of ${raids.length} raids` },
  ];

  return (
    <section className="rounded bg-neutral-800 p-4">
      <h2 className="font-bold">Dungeons &amp; Raids</h2>
      {places.length === 0 ? (
        <p className="mt-2 text-sm text-gray-400">No dungeon or raid statistics synced yet.</p>
      ) : (
        <>
          <div className="mt-2 grid grid-cols-2 gap-2">
            {tiles.map((t) => (
              <div key={t.label} className="rounded border border-neutral-700 bg-neutral-900/60 px-3 py-2">
                <div className="text-2xl font-bold text-amber-300">{t.value.toLocaleString()}</div>
                <div className="text-sm text-gray-300">{t.label}</div>
                <div className="text-xs text-gray-500">{t.sub}</div>
              </div>
            ))}
          </div>
          {(dungeonsEntered > 0 || raidsEntered > 0) && (
            <p className="mt-2 text-xs text-gray-400">
              Entered {dungeonsEntered.toLocaleString()} dungeon{dungeonsEntered === 1 ? "" : "s"}
              {raidsEntered > 0 && ` and ${raidsEntered.toLocaleString()} raid${raidsEntered === 1 ? "" : "s"}`}
            </p>
          )}
          {cleared.length > 0 && (
            <dl className="mt-3 grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
              {cleared.map((p) => (
                <div key={p.place} className="contents">
                  <dt className="text-gray-400">
                    {p.place}
                    {p.raid && <span className="ml-1.5 rounded bg-purple-900/60 px-1 text-[10px] text-purple-200">RAID</span>}
                  </dt>
                  <dd className="text-right">{p.clears.toLocaleString()}×</dd>
                </div>
              ))}
            </dl>
          )}
        </>
      )}
    </section>
  );
}
