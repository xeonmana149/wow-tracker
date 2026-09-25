"use client";

import { useState } from "react";
import { classIcon } from "../../lib/icons";
import CharacterCard, { type CardCharacter } from "../CharacterCard";
import GameIcon from "../GameIcon";
import type { AccountAchievementKind } from "../../lib/accountAchievements";

export type FriendPlayer = {
  id: string;
  name: string;
  characters: CardCharacter[];
  // Kept on the type (populated or not) so callers that still fetch this
  // don't need changing - the account-wide achievements DISPLAY is what's
  // off for now (2026-09-25), via the removed <AccountBadges> below. May
  // come back later.
  accountAchievements?: AccountAchievementKind[];
};

export default function FriendsBrowser({
  players,
  treeNames,
  specIcons,
}: {
  players: FriendPlayer[];
  treeNames: Record<string, string[]>;
  specIcons: Record<string, string>;
}) {
  const [selected, setSelected] = useState("all");

  const everyone = players
    .flatMap((p) => p.characters.map((c) => ({ c, owner: p.name })))
    .sort((a, b) => b.c.level - a.c.level);

  const current = players.find((p) => p.id === selected) ?? null;
  const shown = current
    ? current.characters.map((c) => ({ c, owner: current.name }))
    : everyone;

  return (
    <div className="mt-6 flex flex-col gap-4">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-start">
      {/* The list of friends. It never moves, only what's on the right changes. */}
      <aside className="lg:sticky lg:top-4 lg:w-72 lg:shrink-0">
        <div className="flex gap-2 overflow-x-auto pb-1 lg:max-h-[calc(100vh-2rem)] lg:flex-col lg:overflow-y-auto lg:overflow-x-visible">
          <button
            type="button"
            onClick={() => setSelected("all")}
            aria-pressed={selected === "all"}
            className={`friend-tab ${selected === "all" ? "friend-tab-active" : ""}`}
          >
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full border border-amber-900/70 bg-neutral-900 text-amber-200">
              <svg
                viewBox="0 0 24 24"
                width="18"
                height="18"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <circle cx="9" cy="8" r="3.5" />
                <path d="M2.5 20a6.5 6.5 0 0 1 13 0" />
                <circle cx="17.5" cy="9" r="2.5" />
                <path d="M17 14.5a5 5 0 0 1 4.5 5" />
              </svg>
            </span>
            <span className="min-w-0 flex-1">
              <span className="block truncate font-bold">Everyone</span>
              <span className="sub block truncate text-xs text-gray-400">
                {everyone.length} characters · {players.length}{" "}
                {players.length === 1 ? "player" : "players"}
              </span>
            </span>
          </button>

          {players.map((p) => {
            const active = selected === p.id;
            const highest = Math.max(...p.characters.map((c) => c.level));
            return (
              <button
                key={p.id}
                type="button"
                onClick={() => setSelected(p.id)}
                aria-pressed={active}
                className={`friend-tab ${active ? "friend-tab-active" : ""}`}
                style={{ alignItems: "flex-start" }}
              >
                <span className="flex shrink-0 -space-x-3 pt-0.5">
                  {p.characters.slice(0, 3).map((c) => (
                    <GameIcon
                      key={c.id}
                      name={classIcon(c.class)}
                      label={c.class}
                      size={32}
                      round
                    />
                  ))}
                </span>
                <span className="min-w-0 flex-1 text-left">
                  <span className="block truncate font-bold">{p.name}</span>
                  <span className="sub mt-1 block truncate text-xs text-gray-400">
                    {p.characters.length}{" "}
                    {p.characters.length === 1 ? "character" : "characters"} · highest level{" "}
                    {highest}
                  </span>
                </span>
              </button>
            );
          })}
        </div>
      </aside>

      <section className="min-w-0 flex-1">
        <div className="mb-3 flex flex-wrap items-baseline gap-x-3">
          <h2 className="text-xl font-bold">{current ? current.name : "Everyone"}</h2>
          <p className="text-sm text-gray-400">
            {shown.length} {shown.length === 1 ? "character" : "characters"}
            {!current && " · highest level first"}
          </p>
        </div>

        <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
          {shown.map(({ c, owner }) => (
            <div key={c.id}>
              {!current && <div className="mb-1 pl-1 text-xs text-gray-500">{owner}</div>}
              <CharacterCard
                c={c}
                treeNames={treeNames[c.class]}
                specIcons={specIcons}
                showNeedsAttention={false}
              />
            </div>
          ))}
        </div>
      </section>
      </div>
    </div>
  );
}