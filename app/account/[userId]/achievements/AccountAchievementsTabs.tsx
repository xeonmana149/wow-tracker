"use client";

import { useState } from "react";
import type { CharacterRow } from "../../../../lib/accountView";
import CharacterAchievementsPage from "../../../CharacterAchievementsPage";

// Character tab strip for the Account Achievements page (2026-10-03) -
// deliberately thin: it just picks which character is selected and hands
// that id straight to the EXISTING per-character achievement browser
// (CharacterAchievementsPage, the same component /character/[id]/achievements
// already uses) rather than rebuilding any of its filtering/sorting/pin
// logic here. That component fetches its own data client-side and already
// handles the public-viewer-vs-owner distinction (only the real owner sees
// the pin-to-showcase controls), so it works unchanged no matter whose
// account page this is reached from.
export default function AccountAchievementsTabs({
  characters,
  mainCharacterId,
}: {
  characters: CharacterRow[];
  mainCharacterId: string | null;
}) {
  // Defaults to the account's Main character (same convention as the
  // Overview page's "Main Character Achievements" card) when one's set,
  // otherwise whichever character comes first.
  const [selectedId, setSelectedId] = useState<string>(mainCharacterId ?? characters[0].id);

  return (
    <div>
      <div className="mt-2 flex flex-wrap gap-1.5">
        {characters.map((c) => (
          <button
            key={c.id}
            type="button"
            onClick={() => setSelectedId(c.id)}
            className={`tab-btn px-3 py-1.5 text-sm ${selectedId === c.id ? "tab-btn-active" : ""}`}
          >
            {c.name}
            {c.character_type === "Main" && <span className="ml-1 text-amber-400">★</span>}
          </button>
        ))}
      </div>

      <div className="mt-3 rounded-md border border-neutral-700 bg-neutral-900/40">
        <CharacterAchievementsPage characterId={selectedId} />
      </div>
    </div>
  );
}
