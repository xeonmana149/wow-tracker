"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";
import { Empty, Panel } from "../auction/ui";

type Track = { title: string; artist: string | null; permalinkUrl: string | null; artworkUrl: string | null };
type Station = { slug: string; name: string; description: string | null; listeners: number; track: Track | null };
type Code = { code: string; appLink: string; expiresAt: number };

const label = (t: Track) => `${t.title}${t.artist ? ` - ${t.artist}` : ""}`;

export default function RadioHome() {
  const [stations, setStations] = useState<Station[] | null>(null);
  const [stationsError, setStationsError] = useState(false);
  const [signedIn, setSignedIn] = useState<boolean | null>(null);
  const [code, setCode] = useState<Code | null>(null);
  const [codeError, setCodeError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const res = await fetch("/api/radio/stations", { cache: "no-store" });
        if (!res.ok) throw new Error();
        const json = (await res.json()) as { stations: Station[] };
        if (alive) {
          setStations(json.stations);
          setStationsError(false);
        }
      } catch {
        if (alive) setStationsError(true);
      }
    };
    load();
    const id = setInterval(load, 20000);
    supabase.auth.getSession().then(({ data }) => {
      if (alive) setSignedIn(!!data.session);
    });
    return () => {
      alive = false;
      clearInterval(id);
    };
  }, []);

  useEffect(() => {
    if (!code) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [code]);

  async function getCode() {
    setBusy(true);
    setCodeError(null);
    try {
      const { data } = await supabase.auth.getSession();
      const token = data.session?.access_token;
      if (!token) {
        setSignedIn(false);
        return;
      }
      const res = await fetch("/api/radio/link/code", { method: "POST", headers: { Authorization: `Bearer ${token}` } });
      const json = await res.json();
      if (!res.ok) throw new Error(json.error || "Couldn't make a code.");
      setCode({ code: json.code, appLink: json.appLink, expiresAt: Date.now() + json.expiresInSeconds * 1000 });
      setNow(Date.now());
    } catch (e) {
      setCodeError(e instanceof Error ? e.message : "Couldn't make a code.");
    } finally {
      setBusy(false);
    }
  }

  const left = code ? Math.max(0, Math.round((code.expiresAt - now) / 1000)) : 0;

  return (
    <div className="space-y-4">
      <Panel>
        <h2 className="mb-2 font-semibold text-gray-100">On air now</h2>
        {stationsError && !stations ? (
          <p className="text-sm text-gray-400">The stations aren&apos;t reachable right now - try again in a minute.</p>
        ) : !stations ? (
          <p className="text-sm text-gray-400">Loading stations...</p>
        ) : stations.length === 0 ? (
          <p className="text-sm text-gray-400">No stations yet.</p>
        ) : (
          <ul className="divide-y divide-neutral-800">
            {stations.map((s) => (
              <li key={s.slug} className="flex items-center gap-3 py-2">
                {s.track?.artworkUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={s.track.artworkUrl} alt="" width={44} height={44} className="h-11 w-11 rounded object-cover" />
                ) : (
                  <div className="h-11 w-11 rounded bg-neutral-800" />
                )}
                <div className="min-w-0 flex-1">
                  <div className="font-semibold text-amber-100">{s.name}</div>
                  <div className="truncate text-sm text-gray-400">
                    {!s.track ? (
                      "Nothing playing - the host hasn't added songs yet"
                    ) : s.track.permalinkUrl ? (
                      <a href={s.track.permalinkUrl} target="_blank" rel="noopener noreferrer" className="hover:underline">
                        {label(s.track)}
                      </a>
                    ) : (
                      label(s.track)
                    )}
                  </div>
                </div>
                <div className="shrink-0 text-right text-xs text-gray-500">
                  {s.listeners} {s.listeners === 1 ? "listener" : "listeners"}
                </div>
              </li>
            ))}
          </ul>
        )}
      </Panel>

      <Panel>
        <h2 className="mb-1 font-semibold text-gray-100">Tune in from the desktop app</h2>
        <p className="mb-3 text-sm text-gray-400">
          Open the WoW Forever Tracker app&apos;s tray menu, choose Azeroth Radio, and pick a station. To request songs and vote,
          connect the app to your account with a one-time code. The app gets a key that only works for the radio.
        </p>
        {signedIn === false ? (
          <Empty>
            <Link href="/login" className="text-amber-300 hover:underline">
              Log in
            </Link>{" "}
            to connect the app to your account.
          </Empty>
        ) : code && left > 0 ? (
          <div className="space-y-2">
            <div className="font-mono text-3xl tracking-widest text-amber-200">{code.code}</div>
            <p className="text-sm text-gray-400">
              Type this into the radio&apos;s Settings in the app, or{" "}
              <a href={code.appLink} className="text-amber-300 hover:underline">
                open it in the app
              </a>
              . It works once and runs out in {Math.floor(left / 60)}:{String(left % 60).padStart(2, "0")}.
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            <button
              onClick={getCode}
              disabled={busy || signedIn === null}
              className="rounded border border-amber-600/60 bg-amber-900/30 px-3 py-1.5 text-sm font-semibold text-amber-100 hover:bg-amber-800/40 disabled:opacity-50"
            >
              {busy ? "Getting a code..." : code ? "Get a new code" : "Get a code"}
            </button>
            {code && <p className="text-sm text-gray-400">That code ran out.</p>}
            {codeError && <p className="text-sm text-red-300">{codeError}</p>}
          </div>
        )}
      </Panel>
    </div>
  );
}
