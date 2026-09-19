import { RACIALS, type Racial } from "../../../lib/racials";
import { RACE_ICONS, norm } from "../../../lib/icons";
import { loadIcons } from "../../../lib/server-data";
import GameIcon from "../../GameIcon";

function RacialList({
  title,
  items,
  abilityIcons,
}: {
  title: string;
  items: Racial[];
  abilityIcons: Record<string, string>;
}) {
  return (
    <div>
      <h3 className="text-sm text-gray-400">{title}</h3>
      <ul className="mt-1 flex flex-col gap-2">
        {items.map((r) => (
          <li key={r.name} className="flex gap-3 rounded bg-neutral-900 p-3 text-sm">
            <GameIcon name={abilityIcons[norm(r.name)]} label={r.name} size={38} />
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
  const racials = RACIALS[race] ?? [];
  if (racials.length === 0) return null;

  const { races, abilities } = await loadIcons();
  const raceIcon = races[race] ?? RACE_ICONS[race];

  return (
    <section className="mt-4 max-w-2xl rounded bg-neutral-800 p-4">
      <div className="flex items-center gap-3">
        <GameIcon name={raceIcon} label={race} size={44} round />
        <h2 className="font-bold">{race} Racials</h2>
      </div>
      <div className="mt-3 grid gap-4 sm:grid-cols-2">
        <RacialList
          title="Actives"
          items={racials.filter((r) => r.kind === "Active")}
          abilityIcons={abilities}
        />
        <RacialList
          title="Passives"
          items={racials.filter((r) => r.kind === "Passive")}
          abilityIcons={abilities}
        />
      </div>
    </section>
  );
}