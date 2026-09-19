import Link from "next/link";
import { RACE_FACTION } from "../lib/options";
import {
  PRIMARY_PROFESSIONS,
  PROFESSION_ICONS,
  RACE_ICONS,
  classIcon,
} from "../lib/icons";
import GameIcon from "./GameIcon";

export type CardCharacter = {
  id: string;
  name: string;
  race: string;
  class: string;
  level: number;
  guild: string | null;
  character_type: string;
  ruleset: string | null;
  main_spec: string | null;
  main_role: string;
  off_spec: string | null;
  off_role: string | null;
  gold?: number;
  character_professions: { profession: string; skill: number }[];
  character_talents: { slot: number; tree: string; rank: number }[];
};

// Points in each tree for one spec, like 0/32/10
function talentSplit(c: CardCharacter, slot: number, treeNames: string[] | undefined) {
  const per: Record<string, number> = {};
  for (const r of c.character_talents ?? []) {
    if (r.slot === slot) per[r.tree] = (per[r.tree] ?? 0) + r.rank;
  }
  const names = treeNames && treeNames.length > 0 ? treeNames : Object.keys(per);
  return names.length > 0 ? names.map((n) => per[n] ?? 0).join("/") : "-";
}

export default function CharacterCard({
  c,
  treeNames,
  specIcons,
}: {
  c: CardCharacter;
  treeNames: string[] | undefined;
  specIcons: Record<string, string>;
}) {
  const faction = RACE_FACTION[c.race];
  const professions = (c.character_professions ?? [])
    .filter((p) => PRIMARY_PROFESSIONS.includes(p.profession))
    .sort((a, b) => b.skill - a.skill)
    .slice(0, 2);

  return (
    <Link
      href={`/character/${c.id}`}
      className="block rounded bg-neutral-800 p-4 hover:bg-neutral-700"
    >
      <div className="flex items-start gap-3">
        <GameIcon name={classIcon(c.class)} label={c.class} size={52} round />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-lg font-bold text-white">{c.name}</span>
            <span className="rounded bg-neutral-600 px-2 py-0.5 text-xs">{c.character_type}</span>
          </div>
          <div className="mt-1 flex items-center gap-2 text-sm text-gray-400">
            <GameIcon name={RACE_ICONS[c.race]} label={c.race} size={20} round />
            <span>
              Level {c.level} {c.race} {c.class}
            </span>
          </div>
        </div>
      </div>

      <div className="mt-3 flex flex-wrap gap-2">
        {faction && (
          <span className={`chip ${faction === "Alliance" ? "chip-alliance" : "chip-horde"}`}>
            {faction}
          </span>
        )}
        {c.ruleset && <span className="chip">{c.ruleset}</span>}
        {c.guild && <span className="chip">{`<${c.guild}>`}</span>}
      </div>

      <div className="mt-3 flex flex-col gap-2 text-sm">
        <div className="flex items-center gap-2">
          <GameIcon
            name={c.main_spec ? specIcons[`${c.class}|${c.main_spec}`] : null}
            label={c.main_spec ?? "Spec"}
            size={28}
          />
          <span>
            {c.main_spec || "No spec"}{" "}
            <span className="text-gray-400">({c.main_role})</span>
          </span>
          <span className="ml-auto font-bold text-amber-400" title="Talent points in each tree">
            {talentSplit(c, 1, treeNames)}
          </span>
        </div>

        {c.off_spec && (
          <div className="flex items-center gap-2">
            <GameIcon
              name={specIcons[`${c.class}|${c.off_spec}`]}
              label={c.off_spec}
              size={28}
            />
            <span>
              {c.off_spec}
              {c.off_role && <span className="text-gray-400"> ({c.off_role})</span>}
            </span>
            <span className="ml-auto font-bold text-amber-400/80" title="Off spec talent points">
              {talentSplit(c, 2, treeNames)}
            </span>
          </div>
        )}

        <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 border-t border-neutral-700 pt-2">
          {professions.length > 0 ? (
            professions.map((p) => (
              <span key={p.profession} className="flex items-center gap-1.5">
                <GameIcon name={PROFESSION_ICONS[p.profession]} label={p.profession} size={22} />
                {p.profession}
                <span className="text-gray-400">{p.skill}</span>
              </span>
            ))
          ) : (
            <span className="text-gray-500">No professions yet</span>
          )}
        </div>
      </div>
    </Link>
  );
}