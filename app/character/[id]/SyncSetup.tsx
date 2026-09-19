"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";

export default function SyncSetup({
  characterId,
  ownerId,
}: {
  characterId: string;
  ownerId: string | null;
}) {
  const [isOwner, setIsOwner] = useState(false);
  const [open, setOpen] = useState(false);
  const [token, setToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setIsOwner(!!ownerId && data.user?.id === ownerId);
    });
  }, [ownerId]);

  useEffect(() => {
    if (!isOwner) return;
    supabase
      .from("character_sync_tokens")
      .select("token")
      .eq("character_id", characterId)
      .maybeSingle()
      .then(({ data }) => {
        if (data?.token) setToken(data.token);
      });
  }, [isOwner, characterId]);

  if (!isOwner) return null;

  async function generateToken() {
    setLoading(true);
    setMessage("");
    const newToken = crypto.randomUUID().replace(/-/g, "");
    const { error } = await supabase
      .from("character_sync_tokens")
      .upsert({ character_id: characterId, token: newToken }, { onConflict: "character_id" });
    if (error) {
      setMessage(error.message);
    } else {
      setToken(newToken);
      setMessage("New token generated. Any old token stops working immediately.");
    }
    setLoading(false);
  }

  return (
    <section className="mt-4 max-w-2xl rounded bg-neutral-800 p-4">
      <div className="flex items-center justify-between">
        <h2 className="font-bold">Auto-Sync Setup</h2>
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
            This token lets the companion app on your PC update this character automatically,
            without logging in through a browser. Treat it like a password - anyone with it can
            overwrite this character&apos;s data.
          </p>

          {token ? (
            <div className="mt-3 rounded bg-neutral-900 p-3">
              <p className="text-xs text-gray-500">Your sync token:</p>
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