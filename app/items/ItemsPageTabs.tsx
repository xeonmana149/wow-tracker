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

  const tabClass = (t: Tab) => `tab-btn ${tab === t ? "tab-btn-active" : ""}`;

  return (
    <div>
      <div className="mb-4 flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => setTab("search")}
          aria-pressed={tab === "search"}
          className={tabClass("search")}
        >
          Item Search
        </button>
        <button
          type="button"
          onClick={() => setTab("crafting")}
          aria-pressed={tab === "crafting"}
          className={tabClass("crafting")}
        >
          Crafting Directory
        </button>
      </div>

      {tab === "search" ? <ItemSearch /> : <CraftingBrowser players={players} />}
    </div>
  );
}