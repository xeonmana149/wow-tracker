"use client";

import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
// ^ Adjust this path depending on where you place this file - it needs to
// point at the same lib/supabase.ts your other components use. If you put
// this file at app/AccountSyncSetup.tsx, "../lib/supabase" is right; one
// folder deeper (e.g. app/dashboard/AccountSyncSetup.tsx) needs
// "../../lib/supabase" instead, same rule as your other components.

export default function AccountSyncSetup() {
  const [userId, setUserId] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
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

  return (
    <section className="mt-4 max-w-2xl rounded bg-neutral-800 p-4">
      <div className="flex items-center justify-between">
        <h2 className="font-bold">Account Auto-Sync Setup</h2>
        <button
          onClick={() => setOpen(!open)}
          className="rounded bg-blue-600 px-3 py-1 text-sm text-white"
        >
          {open ? "Hide" : "Set up"}
        </button>
      </div>

      {open && (
        <>
          <p className="mt-2 text-sm text-gray-400">
            One token for your whole account - paste it into the companion app once, and it keeps
            every character you play in sync, creating a new character on this site automatically
            the first time it sees one it doesn&apos;t recognize yet. Treat it like a password.
          </p>

          {token ? (
            <div className="mt-3 rounded bg-neutral-900 p-3">
              <p className="text-xs text-gray-500">Your account sync token:</p>
              <div className="mt-1 flex flex-wrap items-center gap-3">
                <code className="break-all text-sm text-amber-300">{token}</code>
                <button
                  onClick={copyToken}
                  className="rounded bg-neutral-700 px-3 py-1 text-xs font-semibold text-white hover:bg-neutral-600"
                >
                  {copied ? "Copied!" : "Copy"}
                </button>
              </div>
            </div>
          ) : (
            <p className="mt-3 text-sm text-gray-400">No token generated yet.</p>
          )}

          <button
            onClick={generateToken}
            disabled={loading}
            className="mt-3 rounded bg-blue-600 px-4 py-2 text-white disabled:opacity-50"
          >
            {loading ? "Generating..." : token ? "Generate new token" : "Generate token"}
          </button>

          {message && <p className="mt-3 text-sm text-amber-300">{message}</p>}
        </>
      )}
    </section>
  );
}