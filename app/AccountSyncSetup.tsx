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
              <code className="break-all text-sm text-amber-300">{token}</code>
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