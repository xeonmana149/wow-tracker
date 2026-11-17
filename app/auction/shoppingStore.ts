"use client";

// The shopping list lives in this browser only (it's a planning scratchpad,
// not something to share), under one localStorage key.

export type ListEntry = { kind: "recipe" | "item"; id: number; n: number };

const KEY = "wft-ah-shopping";
const EVENT = "wft-ah-shopping-changed";

// The stored text as-is: a stable value for useSyncExternalStore.
export function readRaw(): string {
  try {
    return localStorage.getItem(KEY) ?? "";
  } catch {
    return "";
  }
}

export function readList(): ListEntry[] {
  return parseList(readRaw());
}

export function parseList(raw: string): ListEntry[] {
  try {
    const list = raw ? (JSON.parse(raw) as ListEntry[]) : [];
    return Array.isArray(list) ? list.filter((e) => e && (e.kind === "recipe" || e.kind === "item") && e.id > 0 && e.n > 0) : [];
  } catch {
    return [];
  }
}

export function writeList(list: ListEntry[]) {
  try {
    localStorage.setItem(KEY, JSON.stringify(list));
  } catch {
    // Private window or storage blocked - the list just won't persist.
  }
  window.dispatchEvent(new Event(EVENT));
}

export function addToList(kind: ListEntry["kind"], id: number, n = 1) {
  const list = readList();
  const hit = list.find((e) => e.kind === kind && e.id === id);
  if (hit) hit.n += n;
  else list.push({ kind, id, n });
  writeList(list);
}

export function onListChange(fn: () => void): () => void {
  window.addEventListener(EVENT, fn);
  window.addEventListener("storage", fn);
  return () => {
    window.removeEventListener(EVENT, fn);
    window.removeEventListener("storage", fn);
  };
}
