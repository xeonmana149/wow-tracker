"use client";

import { useEffect, useState, FormEvent } from "react";
import { supabase } from "../../../lib/supabase";

type WishlistItem = {
  id: string;
  item_name: string;
  note: string | null;
};

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
  const [list, setList] = useState<WishlistItem[]>(items);
  const [name, setName] = useState("");
  const [note, setNote] = useState("");
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
      })
      .select("id, item_name, note")
      .single();

    setSaving(false);
    if (error) {
      setMessage(error.message);
      return;
    }
    if (data) setList((prev) => [...prev, data]);
    setName("");
    setNote("");
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
              className="flex items-start justify-between gap-2 rounded bg-neutral-900 p-2"
            >
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-white">{item.item_name}</p>
                {item.note && <p className="text-xs text-gray-400">{item.note}</p>}
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
