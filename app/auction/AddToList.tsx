"use client";

import { useState } from "react";
import { addToList, type ListEntry } from "./shoppingStore";

export default function AddToList({ kind, id, label = "Add to shopping list" }: { kind: ListEntry["kind"]; id: number; label?: string }) {
  const [added, setAdded] = useState(0);
  return (
    <button
      type="button"
      onClick={() => {
        addToList(kind, id, 1);
        setAdded((n) => n + 1);
      }}
      className="rounded border border-neutral-600 px-2 py-0.5 text-xs text-gray-300 hover:border-amber-500/60 hover:text-amber-200"
    >
      {added ? `Added (${added})` : label}
    </button>
  );
}
