"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { iconUrlForFileId, wowIconUrl } from "../../lib/icons";

export type PreBisEntry = {
  id: string;
  item_id: number;
  slot: string | null;
  item: {
    name: string;
    quality_color: string | null;
    icon: number | null;
    icon_name: string | null;
  } | null;
};

// A per-character "what I'm aiming to wear in each slot" list - separate
// from the general Wishlist above it (character_wishlist), and always tied
// to a real item in the shared database (character_prebis.item_id), since
// "best in slot" only makes sense when there's something concrete to
// compare against. Items are added from the Items page (ItemSearch.tsx's
// details panel), not from a form here - this card is read/remove only.
export default function PreBisCard({
  characterId,
  ownerId,
  items,
}: {
  characterId: string;
  ownerId: string;
  items: PreBisEntry[];
}) {
  const [isOwner, setIsOwner] = useState(false);
  const [list, setList] = useState<PreBisEntry[]>(() =>
    [...items].sort((a, b) => (a.slot ?? "").localeCompare(b.slot ?? ""))
  );
  const [message, setMessage] = useState("");

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setIsOwner(data.user?.id === ownerId));
  }, [ownerId]);

  async function removeItem(id: string) {
    const previous = list;
    setList((l) => l.filter((i) => i.id !== id));
    const { error } = await supabase.from("character_prebis").delete().eq("id", id);
    if (error) {
      setMessage(error.message);
      setList(previous);
    }
  }

  return (
    <section className="rounded bg-neutral-800 p-4">
      <h2 className="font-bold">Pre-BiS</h2>
      <p className="mt-1 text-xs text-gray-500">
        What this character&apos;s aiming to wear in each slot. Add items from the{" "}
        <a href="/items" className="text-blue-400 hover:underline">
          Items page
        </a>{" "}
        - click any result, then &quot;Add to Pre-BiS list&quot; in its details panel.
      </p>

      {list.length === 0 ? (
        <p className="mt-3 text-sm text-gray-400">Nothing on the Pre-BiS list yet.</p>
      ) : (
        <ul className="mt-3 flex flex-col gap-2">
          {list.map((entry) => {
            const color = entry.item?.quality_color ? `#${entry.item.quality_color}` : "#ffffff";
            const iconSrc = entry.item
              ? iconUrlForFileId(entry.item.icon) ??
                (entry.item.icon_name ? wowIconUrl(entry.item.icon_name) : null)
              : null;
            return (
              <li
                key={entry.id}
                className="flex items-center justify-between gap-2 rounded bg-neutral-900 p-2"
              >
                <div className="flex min-w-0 items-center gap-2">
                  <div className="h-8 w-8 flex-shrink-0 overflow-hidden rounded border border-neutral-600 bg-neutral-800">
                    {iconSrc && (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={iconSrc} alt="" className="h-full w-full object-cover" />
                    )}
                  </div>
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium" style={{ color }}>
                      {entry.item?.name ?? `Item ${entry.item_id}`}
                    </p>
                    {entry.slot && <p className="text-xs text-gray-500">{entry.slot}</p>}
                  </div>
                </div>
                {isOwner && (
                  <button
                    onClick={() => removeItem(entry.id)}
                    className="shrink-0 text-xs text-red-400 hover:text-red-300"
                  >
                    Remove
                  </button>
                )}
              </li>
            );
          })}
        </ul>
      )}

      {message && <p className="mt-2 text-xs text-red-400">{message}</p>}
    </section>
  );
}