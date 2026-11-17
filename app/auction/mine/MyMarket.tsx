"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";
import { ago, Empty, ItemIcon, Money, Panel, TD, TH, TR } from "../ui";
import GoldChart from "./GoldChart";

type Ref = { id: number; name: string; color: string; icon: string | null };
type Auction = {
  char: string;
  at: number;
  snapT: number;
  id: number;
  item: Ref;
  qty: number;
  each: number;
  status: "sold" | "gone" | "undercut" | "tied" | "cheapest" | "unknown";
  cheapest: number;
  cheaperQty: number;
  cheaperAuctions: number;
};
type Char = { name: string; faction?: string; level?: number; class?: string; money: number; seen: number };
type Trip = { t: number; secs: number; v: number; cash?: number; zone?: string; who?: string; kills?: number; top: { n: number; item: Ref }[] };
type Zone = { zone: string; trips: number; secs: number; made: number; perHour: number };
type Mine = { empty?: boolean; updated: number; chars: Char[]; auctions: Auction[]; gold: [number, number][]; sessions: Trip[]; byZone: Zone[] };

const STATUS: Record<Auction["status"], { text: string; cls: string }> = {
  undercut: { text: "Undercut", cls: "border-red-500/50 text-red-300" },
  tied: { text: "Same price as others", cls: "border-amber-500/50 text-amber-300" },
  cheapest: { text: "Cheapest", cls: "border-emerald-500/50 text-emerald-300" },
  sold: { text: "Sold - check your mail", cls: "border-emerald-500/50 text-emerald-300" },
  gone: { text: "Gone since you looked", cls: "border-neutral-500/60 text-gray-300" },
  unknown: { text: "Bid only", cls: "border-neutral-600 text-gray-400" },
};

const duration = (s: number) => {
  const h = Math.floor(s / 3600);
  const m = Math.round((s % 3600) / 60);
  return h ? `${h}h ${m}m` : `${m}m`;
};
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const dateLabel = (t: number) => {
  const d = new Date(t * 1000);
  return `${MONTHS[d.getMonth()]} ${d.getDate()}, ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
};

function ItemRef({ item }: { item: Ref }) {
  return (
    <Link href={`/auction/item/${item.id}`} className="inline-flex min-w-0 items-center gap-2 hover:underline">
      <ItemIcon src={item.icon} size={22} />
      <span className="truncate font-semibold" style={{ color: item.color }}>
        {item.name}
      </span>
    </Link>
  );
}

export default function MyMarket() {
  const [state, setState] = useState<"loading" | "signed-out" | "error" | "ready">("loading");
  const [data, setData] = useState<Mine | null>(null);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data: s } = await supabase.auth.getSession();
      const token = s.session?.access_token;
      if (!token) {
        if (alive) setState("signed-out");
        return;
      }
      try {
        const res = await fetch("/api/market/me", { headers: { Authorization: `Bearer ${token}` } });
        if (res.status === 401) {
          if (alive) setState("signed-out");
          return;
        }
        const json = (await res.json()) as Mine;
        if (alive) {
          setData(json);
          setState("ready");
        }
      } catch {
        if (alive) setState("error");
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  if (state === "loading") return <p className="text-sm text-gray-400">Loading your auctions...</p>;
  if (state === "signed-out") {
    return (
      <Empty>
        <Link href="/login" className="text-amber-300 hover:underline">
          Log in
        </Link>{" "}
        to see your auctions, gold and farming trips.
      </Empty>
    );
  }
  if (state === "error" || !data) return <Empty>Couldn&apos;t load your data just now - try again in a minute.</Empty>;
  if (data.empty) {
    return (
      <Empty>
        Nothing from Forever Gold yet. This page fills in from the Forever Gold addon through the WoW Forever Tracker app: open the
        auction house once (so the addon sees your auctions), then log out or /reload. The app sends it within a minute.
      </Empty>
    );
  }

  const totalNow = data.chars.reduce((n, c) => n + c.money, 0);
  const undercut = data.auctions.filter((a) => a.status === "undercut").length;

  return (
    <div className="space-y-4">
      <p className="text-xs text-gray-500">From your Forever Gold addon, last sent {ago(data.updated)}. Only you can see this page.</p>

      <Panel>
        <div className="mb-2 flex flex-wrap items-baseline gap-x-4">
          <h2 className="font-semibold text-gray-100">Your auctions</h2>
          {data.auctions.length > 0 && (
            <span className={`text-sm ${undercut ? "text-red-300" : "text-gray-400"}`}>
              {undercut ? `${undercut} undercut` : "Nothing undercut"}
            </span>
          )}
        </div>
        {data.auctions.length === 0 ? (
          <p className="text-sm text-gray-400">No auctions on record. Open the auction house in game, then log out or /reload.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[680px] text-sm">
              <thead>
                <tr>
                  <th className={TH}>Item</th>
                  <th className={TH}>Character</th>
                  <th className={`${TH} text-right`}>Qty</th>
                  <th className={`${TH} text-right`}>Your price each</th>
                  <th className={`${TH} text-right`}>Cheapest now</th>
                  <th className={TH}>Status</th>
                </tr>
              </thead>
              <tbody>
                {data.auctions.map((a) => (
                  <tr key={`${a.char}-${a.id}-${a.item.id}-${a.each}`} className={TR}>
                    <td className={`${TD} max-w-[260px]`}>
                      <ItemRef item={a.item} />
                    </td>
                    <td className={`${TD} text-gray-300`}>{a.char}</td>
                    <td className={`${TD} text-right tabular-nums`}>{a.qty}</td>
                    <td className={`${TD} text-right`}>{a.each ? <Money c={a.each} /> : "-"}</td>
                    <td className={`${TD} text-right`}>{a.cheapest ? <Money c={a.cheapest} /> : "-"}</td>
                    <td className={TD}>
                      <span className={`rounded border px-1.5 py-0.5 text-xs ${STATUS[a.status].cls}`}>{STATUS[a.status].text}</span>
                      {a.status === "undercut" && (
                        <span className="mt-1 block text-xs text-gray-400">
                          {a.cheaperQty.toLocaleString("en-US")} cheaper in {a.cheaperAuctions} auction{a.cheaperAuctions === 1 ? "" : "s"}
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {data.auctions.length > 0 && (
          <p className="mt-2 text-xs text-gray-500">
            Your list is from {ago(Math.max(...data.auctions.map((a) => a.at)))}; prices from the auction house snapshot{" "}
            {ago(Math.max(...data.auctions.map((a) => a.snapT)))}.
          </p>
        )}
      </Panel>

      <Panel>
        <div className="mb-2 flex flex-wrap items-baseline gap-x-4">
          <h2 className="font-semibold text-gray-100">Your gold</h2>
          <span className="text-sm text-gray-300">
            <Money c={totalNow} /> across {data.chars.length} character{data.chars.length === 1 ? "" : "s"}
          </span>
        </div>
        <GoldChart points={data.gold} />
        <ul className="mt-3 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
          {data.chars.map((c) => (
            <li key={c.name} className="flex items-center gap-2 border-t border-neutral-800 py-1">
              <span className="text-gray-200">{c.name}</span>
              <span className="text-xs text-gray-500">{[c.level ? `level ${c.level}` : "", c.faction].filter(Boolean).join(" ")}</span>
              <span className="ml-auto">
                <Money c={c.money} />
              </span>
            </li>
          ))}
        </ul>
      </Panel>

      <Panel>
        <h2 className="mb-2 font-semibold text-gray-100">Farming trips</h2>
        {data.sessions.length === 0 ? (
          <p className="text-sm text-gray-400">
            No saved trips yet. In game, start the tracker on Forever Gold&apos;s Track tab (or /gold track) and save the trip when you&apos;re
            done.
          </p>
        ) : (
          <>
            <div className="mb-3 overflow-x-auto">
              <table className="w-full min-w-[520px] text-sm">
                <thead>
                  <tr>
                    <th className={TH}>Where</th>
                    <th className={`${TH} text-right`}>Trips</th>
                    <th className={`${TH} text-right`}>Time</th>
                    <th className={`${TH} text-right`}>Made</th>
                    <th className={`${TH} text-right`}>Per hour</th>
                  </tr>
                </thead>
                <tbody>
                  {data.byZone.map((z) => (
                    <tr key={z.zone} className={TR}>
                      <td className={`${TD} text-gray-200`}>{z.zone}</td>
                      <td className={`${TD} text-right tabular-nums`}>{z.trips}</td>
                      <td className={`${TD} text-right tabular-nums`}>{duration(z.secs)}</td>
                      <td className={`${TD} text-right`}>
                        <Money c={z.made} />
                      </td>
                      <td className={`${TD} text-right font-semibold`}>
                        <Money c={z.perHour} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <details>
              <summary className="cursor-pointer text-sm text-gray-400 hover:text-gray-200">Every trip ({data.sessions.length})</summary>
              <div className="mt-2 overflow-x-auto">
                <table className="w-full min-w-[720px] text-sm">
                  <thead>
                    <tr>
                      <th className={TH}>When</th>
                      <th className={TH}>Who</th>
                      <th className={TH}>Where</th>
                      <th className={`${TH} text-right`}>Time</th>
                      <th className={`${TH} text-right`}>Made</th>
                      <th className={`${TH} text-right`}>Kills</th>
                      <th className={TH}>Best loot</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.sessions.map((s) => (
                      <tr key={`${s.t}-${s.who}`} className={TR}>
                        <td className={`${TD} whitespace-nowrap text-gray-400`}>{dateLabel(s.t)}</td>
                        <td className={`${TD} text-gray-300`}>{s.who ?? "-"}</td>
                        <td className={`${TD} text-gray-300`}>{s.zone ?? "-"}</td>
                        <td className={`${TD} text-right tabular-nums`}>{duration(s.secs)}</td>
                        <td className={`${TD} text-right`}>
                          <Money c={s.v} />
                        </td>
                        <td className={`${TD} text-right tabular-nums`}>{s.kills ?? 0}</td>
                        <td className={TD}>
                          <span className="flex flex-wrap gap-2">
                            {s.top.slice(0, 3).map((t) => (
                              <span key={t.item.id} className="inline-flex items-center gap-1 text-xs text-gray-400">
                                <ItemIcon src={t.item.icon} size={16} /> {t.n}
                              </span>
                            ))}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </details>
          </>
        )}
      </Panel>
    </div>
  );
}
