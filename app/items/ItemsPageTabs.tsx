"use client";

import { useState } from "react";
import ItemSearch from "./ItemSearch";
import CraftingBrowser from "./CraftingBrowser";
import type { CraftingPlayer } from "./craftingTypes";

type Tab = "search" | "crafting";

// Item Search and the old standalone Crafting Directory answer two related
// but different questions - "I have an item, who can make it" vs "who has
// profession X, and are we missing any" - so rather than force one into the
// other, they live side by side here as tabs on the same page. Item Search
// stays the default/first tab since that's the main use of this page.
export default function ItemsPageTabs({
  players,
  initialTab = "search",
}: {
  players: CraftingPlayer[];
  initialTab?: Tab;
}) {
  const [tab, setTab] = useState<Tab>(initialTab);

  const tabClass = (t: Tab) =>
    `border-b-2 px-3 py-2 text-sm font-medium transition-colors ${
      tab === t
        ? "border-amber-400 text-white"
        : "border-transparent text-gray-400 hover:text-white"
    }`;

  return (
    <div>
      <div className="mb-4 flex gap-1 border-b border-neutral-800">
        <button type="button" onClick={() => setTab("search")} className={tabClass("search")}>
          Item Search
        </button>
        <button type="button" onClick={() => setTab("crafting")} className={tabClass("crafting")}>
          Crafting Directory
        </button>
      </div>

      {tab === "search" ? <ItemSearch /> : <CraftingBrowser players={players} />}
    </div>
  );
}