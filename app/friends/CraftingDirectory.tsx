import Link from "next/link";
import { PRIMARY_PROFESSIONS, PROFESSION_ICONS, classIcon } from "../../lib/icons";
import { MAX_SKILL, SECONDARY_PROFESSIONS, SUPPLIED_BY } from "../../lib/professions";
import GameIcon from "../GameIcon";
import type { FriendPlayer } from "./FriendsBrowser";

type Entry = { id: string; name: string; cls: string; owner: string; skill: number };

// Everyone in the group who has this profession, best first
function crafters(players: FriendPlayer[], profession: string): Entry[] {
  const out: Entry[] = [];
  for (const p of players) {
    for (const c of p.characters) {
      for (const pr of c.character_professions ?? []) {
        if (pr.profession === profession) {
          out.push({ id: c.id, name: c.name, cls: c.class, owner: p.name, skill: pr.skill });
        }
      }
    }
  }
  return out.sort((a, b) => b.skill - a.skill);
}

function ProfessionCard({
  profession,
  list,
  counts,
}: {
  profession: string;
  list: Entry[];
  counts: Record<string, number>;
}) {
  const supplier = SUPPLIED_BY[profession];

  return (
    <section className="rounded bg-neutral-800 p-4">
      <div className="flex items-center gap-3">
        <GameIcon name={PROFESSION_ICONS[profession]} label={profession} size={40} />
        <div className="min-w-0 flex-1">
          <h3 className="text-lg font-bold">{profession}</h3>
          <p className={`text-sm ${list.length === 0 ? "text-red-400" : "text-gray-400"}`}>
            {list.length === 0
              ? "Nobody has this yet"
              : `${list.length} ${list.length === 1 ? "character" : "characters"}`}
          </p>
        </div>
      </div>

      {list.length > 0 && (
        <ul className="mt-3 flex flex-col gap-2">
          {list.slice(0, 6).map((e) => (
            <li key={e.id}>
              <Link
                href={`/character/${e.id}`}
                className="flex items-center gap-2 rounded px-1 py-0.5 hover:bg-neutral-900"
              >
                <GameIcon name={classIcon(e.cls)} label={e.cls} size={24} round />
                <span className="min-w-0 flex-1 truncate">
                  <span className="font-bold text-white">{e.name}</span>{" "}
                  <span className="text-xs text-gray-500">{e.owner}</span>
                </span>
                <span className={e.skill >= MAX_SKILL ? "font-bold text-yellow-300" : "text-gray-300"}>
                  {e.skill}
                </span>
              </Link>
              <div className="mt-0.5 h-1 rounded bg-neutral-700">
                <div
                  className={`h-1 rounded ${e.skill >= MAX_SKILL ? "bg-yellow-500" : "bg-blue-500"}`}
                  style={{ width: `${Math.min(100, (e.skill / MAX_SKILL) * 100)}%` }}
                />
              </div>
            </li>
          ))}
          {list.length > 6 && (
            <li className="text-xs text-gray-500">+{list.length - 6} more</li>
          )}
        </ul>
      )}

      {supplier && (
        <p className="mt-3 border-t border-neutral-700 pt-2 text-xs text-gray-500">
          Materials come from {supplier}: {counts[supplier] ?? 0} in the group
        </p>
      )}
    </section>
  );
}

export default function CraftingDirectory({ players }: { players: FriendPlayer[] }) {
  const lists: Record<string, Entry[]> = {};
  const counts: Record<string, number> = {};
  for (const p of [...PRIMARY_PROFESSIONS, ...SECONDARY_PROFESSIONS]) {
    lists[p] = crafters(players, p);
    counts[p] = lists[p].length;
  }

  const missing = PRIMARY_PROFESSIONS.filter((p) => lists[p].length === 0);

  return (
    <div>
      <div className="mb-4">
        <h2 className="text-xl font-bold">Crafting directory</h2>
        <p className="mt-1 text-sm text-gray-400">
          Who can make what across the whole group, best skill first.
        </p>
        {missing.length > 0 ? (
          <p className="mt-2 text-sm text-red-400">
            Nobody in the group has: {missing.join(", ")}
          </p>
        ) : (
          <p className="mt-2 text-sm text-green-400">Every primary profession is covered.</p>
        )}
      </div>

      <h3 className="text-sm text-gray-400">Primary professions</h3>
      <div className="mt-2 grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
        {PRIMARY_PROFESSIONS.map((p) => (
          <ProfessionCard key={p} profession={p} list={lists[p]} counts={counts} />
        ))}
      </div>

      <h3 className="mt-6 text-sm text-gray-400">Secondary professions</h3>
      <div className="mt-2 grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
        {SECONDARY_PROFESSIONS.map((p) => (
          <ProfessionCard key={p} profession={p} list={lists[p]} counts={counts} />
        ))}
      </div>
    </div>
  );
}