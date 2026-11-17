"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { onListChange, parseList, readRaw, writeList, type ListEntry } from "../shoppingStore";
import { Empty, ItemIcon, Money, Panel, TD, TH, TR } from "../ui";

type Ref = { id: number; name: string; color: string; icon: string | null };
type PricedEntry = ListEntry & { name: string; prof?: string; made?: Ref | null; makes?: number; worth?: number; missing?: boolean };
type BuyLine = Ref & { qty: number; cost: number; got: number; from: "vendor" | "ah" | "mixed" | null; dearest: number };
type Priced = { snapT: number; entries: PricedEntry[]; buy: BuyLine[]; total: number; worth: number };

const FROM: Record<string, string> = { vendor: "vendor", ah: "auction house", mixed: "auction + vendor" };

export default function ShoppingList() {
  const house = useSearchParams().get("house");
  // null on the server and in the first client render, so hydration matches.
  const raw = useSyncExternalStore(onListChange, readRaw, () => null);
  const list = useMemo<ListEntry[] | null>(() => (raw === null ? null : parseList(raw)), [raw]);
  const [priced, setPriced] = useState<Priced | null>(null);
  const [error, setError] = useState<string | null>(null);

  const price = useCallback(
    async (l: ListEntry[]) => {
      if (l.length === 0) {
        setPriced(null);
        return;
      }
      try {
        const res = await fetch("/api/market/shopping", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ house: house ? Number(house) : undefined, list: l }),
        });
        if (!res.ok) throw new Error((await res.json().catch(() => null))?.error ?? `HTTP ${res.status}`);
        setPriced(await res.json());
        setError(null);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Couldn't price the list");
      }
    },
    [house]
  );

  useEffect(() => {
    if (!list) return;
    const t = setTimeout(() => price(list), 250);
    return () => clearTimeout(t);
  }, [list, price]);

  const setN = (i: number, n: number) => {
    if (!list) return;
    const next = list.map((e, k) => (k === i ? { ...e, n: Math.max(1, Math.min(1000, n || 1)) } : e));
    writeList(next);
  };
  const remove = (i: number) => list && writeList(list.filter((_, k) => k !== i));

  if (list === null) return <p className="text-sm text-gray-400">Loading your list...</p>;
  if (list.length === 0) {
    return (
      <Empty>
        Your shopping list is empty. Add crafts from{" "}
        <Link className="text-amber-300 hover:underline" href={`/auction/crafting${house ? `?house=${house}` : ""}`}>
          Crafting profits
        </Link>{" "}
        or any item page, and this works out exactly what to buy and what it costs from the cheapest listings up. The list is kept in
        this browser.
      </Empty>
    );
  }

  const byKey = new Map(priced?.entries.map((e) => [`${e.kind}:${e.id}`, e]) ?? []);
  const profit = priced ? priced.worth - priced.total : 0;

  return (
    <div className="space-y-4">
      <Panel>
        <div className="mb-2 flex items-center gap-3">
          <h2 className="font-semibold text-gray-100">What you want</h2>
          <button type="button" onClick={() => writeList([])} className="ml-auto text-xs text-gray-400 hover:text-red-300">
            Clear the list
          </button>
        </div>
        <ul className="divide-y divide-neutral-800">
          {list.map((e, i) => {
            const p = byKey.get(`${e.kind}:${e.id}`);
            return (
              <li key={`${e.kind}:${e.id}`} className="flex flex-wrap items-center gap-3 py-2">
                <input
                  type="number"
                  min={1}
                  max={1000}
                  value={e.n}
                  onChange={(ev) => setN(i, Number(ev.target.value))}
                  className="w-20 rounded border border-neutral-700 bg-neutral-900 px-2 py-1 text-sm text-gray-100"
                  aria-label="How many"
                />
                <span className="text-xs text-gray-500">{e.kind === "recipe" ? "crafts of" : "x"}</span>
                {p?.made ? (
                  <Link href={`/auction/item/${p.made.id}${house ? `?house=${house}` : ""}`} className="inline-flex items-center gap-2 hover:underline">
                    <ItemIcon src={p.made.icon} size={22} />
                    <span className="font-semibold" style={{ color: p.made.color }}>
                      {e.kind === "recipe" ? p.name : p.made.name}
                    </span>
                  </Link>
                ) : (
                  <span className="text-gray-300">{p?.name ?? `#${e.id}`}</span>
                )}
                {p?.prof && <span className="text-xs text-gray-500">{p.prof}</span>}
                {e.kind === "recipe" && p?.makes !== undefined && p.makes !== e.n && <span className="text-xs text-gray-500">makes {p.makes}</span>}
                <span className="ml-auto flex items-center gap-3 text-sm">
                  {p?.worth ? (
                    <span className="text-gray-400">
                      sells for about <Money c={p.worth} />
                    </span>
                  ) : null}
                  <button type="button" onClick={() => remove(i)} className="text-xs text-gray-500 hover:text-red-300" aria-label="Remove">
                    Remove
                  </button>
                </span>
              </li>
            );
          })}
        </ul>
      </Panel>

      {error && <p className="text-sm text-red-300">{error}</p>}

      {priced && (
        <Panel>
          <div className="mb-3 flex flex-wrap items-baseline gap-x-6 gap-y-1">
            <h2 className="font-semibold text-gray-100">What to buy</h2>
            <span className="text-sm text-gray-300">
              Total <Money c={priced.total} />
            </span>
            {priced.worth > 0 && (
              <span className="text-sm text-gray-300">
                Crafts sell for about <Money c={priced.worth} /> after the cut:{" "}
                <span className={profit >= 0 ? "text-emerald-300" : "text-red-300"}>
                  <Money c={profit} sign />
                </span>
              </span>
            )}
          </div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[620px] text-sm">
              <thead>
                <tr>
                  <th className={TH}>Item</th>
                  <th className={`${TH} text-right`}>Need</th>
                  <th className={`${TH} text-right`}>Costs</th>
                  <th className={`${TH} text-right`}>Pay up to</th>
                  <th className={TH}>From</th>
                </tr>
              </thead>
              <tbody>
                {priced.buy.map((b) => (
                  <tr key={b.id} className={TR}>
                    <td className={TD}>
                      <Link href={`/auction/item/${b.id}${house ? `?house=${house}` : ""}`} className="inline-flex items-center gap-2 hover:underline">
                        <ItemIcon src={b.icon} size={22} />
                        <span className="font-semibold" style={{ color: b.color }}>
                          {b.name}
                        </span>
                      </Link>
                    </td>
                    <td className={`${TD} text-right tabular-nums`}>{b.qty.toLocaleString("en-US")}</td>
                    <td className={`${TD} text-right`}>
                      <Money c={b.cost} />
                    </td>
                    <td className={`${TD} text-right`}>{b.dearest ? <Money c={b.dearest} /> : "-"}</td>
                    <td className={TD}>
                      {b.got < b.qty ? (
                        <span className="text-xs text-amber-300">only {b.got.toLocaleString("en-US")} listed</span>
                      ) : (
                        <span className="text-xs text-gray-400">{b.from ? FROM[b.from] : "-"}</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-2 text-xs text-gray-500">
            &quot;Pay up to&quot; is the dearest single listing you&apos;d need to buy. Prices are from the latest hourly snapshot.
          </p>
        </Panel>
      )}
    </div>
  );
}
