"use client";

import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
// ^ Adjust this path depending on where you place this file - it needs to
// point at the same lib/supabase.ts your other components use. If you put
// this file at app/AccountSyncSetup.tsx, "../lib/supabase" is right; one
// folder deeper (e.g. app/dashboard/AccountSyncSetup.tsx) needs
// "../../lib/supabase" instead, same rule as your other components.

// Custom URL scheme the tray app (v2.2.6+) registers with Windows. This
// replaced http://127.0.0.1:47891/setup (2026-11-05) - that was the old
// plain-Node sync.js's local setup page, and the Electron tray app has no
// HTTP server, so the old link just failed to load.
const SYNC_APP_PROTOCOL = "wowforever";

export default function AccountSyncSetup({ openSignal }: { openSignal?: number } = {}) {
  const [userId, setUserId] = useState<string | null>(null);
  const [open, setOpen] = useState(false);

  // The Dashboard's "Set Up Auto-Sync" stat-strip button is the only way to
  // open this now (there's no header/toggle of its own) - every increment
  // of openSignal just means "someone wants this open now".
  useEffect(() => {
    if (openSignal !== undefined && openSignal > 0) setOpen(true);
  }, [openSignal]);
  const [token, setToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setUserId(data.user?.id ?? null);
    });
  }, []);

  useEffect(() => {
    if (!userId) return;
    supabase
      .from("user_sync_tokens")
      .select("token")
      .eq("user_id", userId)
      .maybeSingle()
      .then(({ data }) => {
        if (data?.token) setToken(data.token);
      });
  }, [userId]);

  if (!userId) return null;

  async function generateToken() {
    setLoading(true);
    setMessage("");
    const newToken = crypto.randomUUID().replace(/-/g, "");
    const { error } = await supabase
      .from("user_sync_tokens")
      .upsert({ user_id: userId, token: newToken }, { onConflict: "user_id" });
    if (error) {
      setMessage(error.message);
    } else {
      setToken(newToken);
      setMessage(
        "New token generated. Any old token stops working immediately - the companion app on every PC using the old one will need the new one pasted in."
      );
    }
    setLoading(false);
  }

  async function copyToken() {
    if (!token) return;
    try {
      await navigator.clipboard.writeText(token);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard access can fail (e.g. an insecure/non-HTTPS context, or a
      // browser that blocks it) - fall back to just letting them select and
      // copy the text manually, since it's already shown right there.
      setMessage("Couldn't copy automatically - select the token above and copy it manually.");
    }
  }

  // "Open Sync App" (below) hands the token to the companion app through
  // its wowforever:// link - Windows launches the app if it isn't running,
  // the app saves the token and opens its Settings window. Only works once
  // the app (v2.2.6+) is installed on THIS computer; if it isn't, the
  // browser just does nothing, so Copy stays as the fallback for a second
  // PC or a first-time install. A plain <a href> rather than JS navigation.

  // No standalone header/box of its own anymore - the Dashboard's own
  // "Set Up Auto-Sync" button is the only way in, so there's nothing to
  // show (and no duplicate title bar sitting around) until that's clicked.
  if (!open) return null;

  return (
    <section className="mt-4 max-w-2xl rounded bg-neutral-800 p-4">
      <div className="flex items-center justify-between">
        <h2 className="font-bold">Account Auto-Sync Setup</h2>
        <button onClick={() => setOpen(false)} className="text-xs text-gray-400 underline">
          Hide
        </button>
      </div>

      <p className="mt-2 text-sm text-gray-400">
        One token for your whole account. If the companion app is installed on this computer,
        &quot;Open Sync App&quot; opens its Settings with the token already filled in - tick your
        characters there and hit Save. Set it up once and it keeps every character
        you play in sync, creating a new character on this site automatically the first time it
        sees one it doesn&apos;t recognize yet. Treat it like a password.
      </p>

      {token ? (
        <div className="mt-3 rounded bg-neutral-900 p-3">
          <p className="text-xs text-gray-500">Your account sync token:</p>
          <div className="mt-1 flex flex-wrap items-center gap-3">
            <code className="break-all text-sm text-amber-300">{token}</code>
            <a
              href={`${SYNC_APP_PROTOCOL}://setup?token=${encodeURIComponent(token)}`}
              className="rounded bg-red-700 px-3 py-1 text-xs"
            >
              Open Sync App
            </a>
            <button
              onClick={copyToken}
              className="rounded bg-neutral-700 px-3 py-1 text-xs font-semibold text-white hover:bg-neutral-600"
            >
              {copied ? "Copied!" : "Copy"}
            </button>
          </div>
          <p className="mt-2 text-xs text-gray-500">
            &quot;Open Sync App&quot; needs the companion app (v2.2.6 or newer) installed on this
            computer. Nothing happens? Use Copy and paste the token into the app&apos;s Settings
            instead.
          </p>
        </div>
      ) : (
        <p className="mt-3 text-sm text-gray-400">No token generated yet.</p>
      )}

      <button
        onClick={generateToken}
        disabled={loading}
        className="mt-3 rounded bg-red-700 px-4 py-2 text-sm disabled:opacity-50"
      >
        {loading ? "Generating..." : token ? "Generate new token" : "Generate token"}
      </button>

      {message && <p className="mt-3 text-sm text-amber-300">{message}</p>}
    </section>
  );
}