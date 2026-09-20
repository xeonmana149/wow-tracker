"use client";

import { useEffect, useState, FormEvent } from "react";
import { supabase } from "../../../lib/supabase";

type Priority = "High" | "Medium" | "Low";

export type WishlistItem = {
  id: string;
  item_name: string;
  note: string | null;
  priority: Priority;
  obtained: boolean;
};

const PRIORITY_ORDER: Record<Priority, number> = { High: 0, Medium: 1, Low: 2 };
const PRIORITY_STYLE: Record<Priority, string> = {
  High: "bg-red-500/20 text-red-300",
  Medium: "bg-amber-500/20 text-amber-300",
  Low: "bg-neutral-600/40 text-gray-300",
};

// Not-yet-obtained items first (that's what you actually need to see at a
// glance), highest priority first within each group, then oldest first.
function sortItems(items: WishlistItem[]) {
  return [...items].sort((a, b) => {
    if (a.obtained !== b.obtained) return a.obtained ? 1 : -1;
    return PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority];
  });
}

export default function WishlistCard({
  characterId,
  ownerId,
  items,
}: {
  characterId: string;
  ownerId: string;
  items: WishlistItem[];
}) {
  const [isOwner, setIsOwner] = useState(false);
  const [list, setList] = useState<WishlistItem[]>(() => sortItems(items));
  const [name, setName] = useState("");
  const [note, setNote] = useState("");
  const [priority, setPriority] = useState<Priority>("Medium");
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setIsOwner(data.user?.id === ownerId));
  }, [ownerId]);

  async function addItem(e: FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    setSaving(true);
    setMessage("");

    const { data: userData } = await supabase.auth.getUser();
    if (!userData.user) {
      setSaving(false);
      setMessage("You need to be logged in to add to the wishlist.");
      return;
    }

    const { data, error } = await supabase
      .from("character_wishlist")
      .insert({
        character_id: characterId,
        user_id: userData.user.id,
        item_name: name.trim(),
        note: note.trim() || null,
        priority,
      })
      .select("id, item_name, note, priority, obtained")
      .single();

    setSaving(false);
    if (error) {
      setMessage(error.message);
      return;
    }
    if (data) setList((prev) => sortItems([...prev, data as WishlistItem]));
    setName("");
    setNote("");
    setPriority("Medium");
  }

  async function removeItem(id: string) {
    // Optimistic - pull it from the list right away, put it back if the
    // delete turns out to have failed (e.g. RLS rejected it).
    const previous = list;
    setList((l) => l.filter((i) => i.id !== id));
    const { error } = await supabase.from("character_wishlist").delete().eq("id", id);
    if (error) {
      setMessage(error.message);
      setList(previous);
    }
  }

  async function toggleObtained(id: string, current: boolean) {
    const previous = list;
    setList((l) => sortItems(l.map((i) => (i.id === id ? { ...i, obtained: !current } : i))));
    const { error } = await supabase
      .from("character_wishlist")
      .update({ obtained: !current })
      .eq("id", id);
    if (error) {
      setMessage(error.message);
      setList(previous);
    }
  }

  return (
    <section className="rounded bg-neutral-800 p-4">
      <h2 className="font-bold">Wishlist / BiS</h2>
      <p className="mt-1 text-xs text-gray-500">
        Items this character&apos;s after - so the group knows what to grab or pass on while
        farming together.
      </p>

      {list.length === 0 ? (
        <p className="mt-3 text-sm text-gray-400">Nothing on the list yet.</p>
      ) : (
        <ul className="mt-3 flex flex-col gap-2">
          {list.map((item) => (
            <li
              key={item.id}
              className={`flex items-start justify-between gap-2 rounded bg-neutral-900 p-2 ${
                item.obtained ? "opacity-50" : ""
              }`}
            >
              <div className="flex min-w-0 items-start gap-2">
                {isOwner && (
                  <input
                    type="checkbox"
                    checked={item.obtained}
                    onChange={() => toggleObtained(item.id, item.obtained)}
                    title="Got it"
                    className="mt-1 h-4 w-4 shrink-0 accent-green-600"
                  />
                )}
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <p
                      className={`truncate text-sm font-medium text-white ${
                        item.obtained ? "line-through" : ""
                      }`}
                    >
                      {item.item_name}
                    </p>
                    <span
                      className={`shrink-0 rounded px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wide ${PRIORITY_STYLE[item.priority]}`}
                    >
                      {item.priority}
                    </span>
                  </div>
                  {item.note && <p className="text-xs text-gray-400">{item.note}</p>}
                </div>
              </div>
              {isOwner && (
                <button
                  onClick={() => removeItem(item.id)}
                  className="shrink-0 text-xs text-red-400 hover:text-red-300"
                >
                  Remove
                </button>
              )}
            </li>
          ))}
        </ul>
      )}

      {isOwner && (
        <form onSubmit={addItem} className="mt-3 flex flex-col gap-2">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Item name"
            className="rounded bg-white p-2 text-sm text-black"
            required
          />
          <input
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Where it drops, or any note (optional)"
            className="rounded bg-white p-2 text-sm text-black"
          />
          <select
            value={priority}
            onChange={(e) => setPriority(e.target.value as Priority)}
            className="rounded bg-white p-2 text-sm text-black"
          >
            <option value="High">High priority</option>
            <option value="Medium">Medium priority</option>
            <option value="Low">Low priority</option>
          </select>
          <button
            type="submit"
            disabled={saving}
            className="self-start rounded bg-blue-600 px-3 py-1.5 text-sm text-white disabled:opacity-50"
          >
            {saving ? "Adding..." : "Add item"}
          </button>
        </form>
      )}

      {message && <p className="mt-2 text-xs text-red-400">{message}</p>}
    </section>
  );
}