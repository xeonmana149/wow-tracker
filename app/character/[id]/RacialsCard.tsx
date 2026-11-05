import type { Racial } from "../../../lib/gameData";
import { RACE_ICONS } from "../../../lib/icons";
import { loadRacials } from "../../../lib/server-data";
import GameIcon from "../../GameIcon";

// Racials come from the current client data (lib/gameData.ts), refreshed
// daily (see lib/server-data.ts) - not a hand-kept list.
function RacialList({ title, items }: { title: string; items: Racial[] }) {
  if (items.length === 0) return null;
  return (
    <div>
      <h3 className="text-sm text-gray-400">{title}</h3>
      <ul className="mt-1 flex flex-col gap-2">
        {items.map((r) => (
          <li key={r.name} className="flex gap-3 rounded bg-neutral-900 p-3 text-sm">
            <GameIcon name={r.icon} label={r.name} size={38} />
            <div className="min-w-0">
              <div className="font-bold">{r.name}</div>
              <div className="mt-0.5 text-gray-400">{r.description}</div>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

export default async function RacialsCard({ race }: { race: string }) {
  const { races } = await loadRacials();
  const entry = races[race];
  if (!entry || entry.abilities.length === 0) return null;

  const raceIcon = entry.icon ?? RACE_ICONS[race];

  return (
    <section className="mt-4 max-w-2xl rounded bg-neutral-800 p-4">
      <div className="flex items-center gap-3">
        <GameIcon name={raceIcon} label={race} size={44} round />
        <h2 className="font-bold">{race} Racials</h2>
      </div>
      <div className="mt-3 grid gap-4 sm:grid-cols-2">
        <RacialList title="Actives" items={entry.abilities.filter((r) => r.kind === "Active")} />
        <RacialList title="Passives" items={entry.abilities.filter((r) => r.kind === "Passive")} />
      </div>
    </section>
  );
}
