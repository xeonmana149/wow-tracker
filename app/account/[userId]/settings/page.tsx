"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { supabase } from "../../../../lib/supabase";

// Account Settings (2026-10-03, "what should this do" -> scoped down from a
// much bigger wishlist to: Profile (default character), Privacy
// (public/private + show playtime/activity), Characters (per-character
// hidden/include-in-statistics), and a basic Notifications tab - see
// sql/account-settings.sql for the backing columns and that file's header
// comment for what "hidden" does and doesn't enforce.
//
// Owner-only, unlike the rest of the /account/[userId]/* pages (Overview,
// Achievements, Statistics, Activity all show the same thing to anyone) -
// editing someone else's settings makes no sense, so this is a "use client"
// page using the browser's RLS-scoped `supabase` client (not supabaseAdmin):
// RLS already only lets you UPDATE your own profiles/characters rows, so a
// visitor hitting this URL for someone else's account simply can't save
// anything even if they tried, on top of the explicit ownership check below.

type CharacterRow = { id: string; name: string; hidden: boolean; include_in_statistics: boolean };

type ProfileSettings = {
  default_character_id: string | null;
  profile_visibility: "public" | "private";
  show_playtime: boolean;
  show_activity: boolean;
  notify_achievement_earned: boolean;
  notify_account_achievement_earned: boolean;
  notify_legacy_completed: boolean;
};

export default function AccountSettingsPage() {
  const params = useParams<{ userId: string }>();
  const userId = params.userId;

  const [loading, setLoading] = useState(true);
  const [isOwner, setIsOwner] = useState(false);
  const [characters, setCharacters] = useState<CharacterRow[]>([]);
  const [settings, setSettings] = useState<ProfileSettings | null>(null);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    async function load() {
      const { data: userData } = await supabase.auth.getUser();
      const owner = userData.user?.id === userId;
      setIsOwner(owner);

      if (owner) {
        const [{ data: profileRow }, { data: characterRows }] = await Promise.all([
          supabase
            .from("profiles")
            .select(
              "default_character_id, profile_visibility, show_playtime, show_activity, notify_achievement_earned, notify_account_achievement_earned, notify_legacy_completed"
            )
            .eq("id", userId)
            .maybeSingle(),
          supabase
            .from("characters")
            .select("id, name, hidden, include_in_statistics")
            .eq("user_id", userId)
            .order("name", { ascending: true }),
        ]);

        setSettings({
          default_character_id: profileRow?.default_character_id ?? null,
          profile_visibility: (profileRow?.profile_visibility as "public" | "private" | undefined) ?? "public",
          show_playtime: profileRow?.show_playtime ?? true,
          show_activity: profileRow?.show_activity ?? true,
          notify_achievement_earned: profileRow?.notify_achievement_earned ?? true,
          notify_account_achievement_earned: profileRow?.notify_account_achievement_earned ?? true,
          notify_legacy_completed: profileRow?.notify_legacy_completed ?? true,
        });
        setCharacters((characterRows ?? []) as CharacterRow[]);
      }
      setLoading(false);
    }
    load();
  }, [userId]);

  function updateCharacter(id: string, patch: Partial<CharacterRow>) {
    setCharacters((prev) => prev.map((c) => (c.id === id ? { ...c, ...patch } : c)));
  }

  async function save() {
    if (!settings) return;
    setSaving(true);
    setMessage("");

    const [{ error: profileError }, ...characterResults] = await Promise.all([
      supabase
        .from("profiles")
        .update({
          default_character_id: settings.default_character_id,
          profile_visibility: settings.profile_visibility,
          show_playtime: settings.show_playtime,
          show_activity: settings.show_activity,
          notify_achievement_earned: settings.notify_achievement_earned,
          notify_account_achievement_earned: settings.notify_account_achievement_earned,
          notify_legacy_completed: settings.notify_legacy_completed,
        })
        .eq("id", userId),
      ...characters.map((c) =>
        supabase
          .from("characters")
          .update({ hidden: c.hidden, include_in_statistics: c.include_in_statistics })
          .eq("id", c.id)
      ),
    ]);

    setSaving(false);
    const failed = profileError ?? characterResults.find((r) => r.error)?.error;
    if (failed) {
      setMessage(failed.message);
    } else {
      setMessage("Saved");
      setTimeout(() => setMessage(""), 1500);
    }
  }

  if (loading) {
    return <main className="mx-auto max-w-3xl p-4 text-white md:p-6">Loading settings...</main>;
  }

  if (!isOwner) {
    return (
      <main className="mx-auto max-w-3xl p-4 text-white md:p-6">
        <h1 className="text-2xl font-bold">Settings</h1>
        <p className="mt-4 text-sm text-gray-400">
          You can only view and edit your own account&apos;s settings.{" "}
          <Link href={`/account/${userId}`} className="text-amber-400 hover:underline">
            ← Back to this account
          </Link>
        </p>
      </main>
    );
  }

  if (!settings) {
    return <main className="mx-auto max-w-3xl p-4 text-white md:p-6">Couldn&apos;t load your settings.</main>;
  }

  return (
    <main className="mx-auto max-w-3xl p-4 text-white md:p-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Settings</h1>
        <Link href={`/account/${userId}`} className="text-xs text-amber-400 hover:underline">
          ← Back to Account
        </Link>
      </div>

      {/* PROFILE */}
      <section className="mt-6 rounded-md border border-neutral-700 bg-neutral-800 p-4">
        <h2 className="text-lg">Profile</h2>
        <p className="mt-1 text-xs text-gray-500">
          Display name, avatar, banner, motto and Showcase picks are edited from{" "}
          <Link href="/account" className="text-amber-400 hover:underline">
            Edit Profile
          </Link>{" "}
          on your Overview page.
        </p>
        <label className="mt-3 block text-sm text-gray-300">
          Default character
          <select
            value={settings.default_character_id ?? ""}
            onChange={(e) => setSettings({ ...settings, default_character_id: e.target.value || null })}
            className="mt-1 block w-full rounded border border-neutral-700 bg-neutral-900 px-2 py-1.5 text-sm text-gray-200"
          >
            <option value="">None set</option>
            {characters.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </label>
      </section>

      {/* PRIVACY */}
      <section className="mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
        <h2 className="text-lg">Privacy</h2>
        <div className="mt-3 flex flex-col gap-2 text-sm">
          <label className="flex items-center gap-2">
            <input
              type="radio"
              name="visibility"
              checked={settings.profile_visibility === "public"}
              onChange={() => setSettings({ ...settings, profile_visibility: "public" })}
            />
            Public - anyone can view your account page
          </label>
          <label className="flex items-center gap-2">
            <input
              type="radio"
              name="visibility"
              checked={settings.profile_visibility === "private"}
              onChange={() => setSettings({ ...settings, profile_visibility: "private" })}
            />
            Private - only you can view your account page
          </label>
          <p className="text-xs text-gray-500">
            There&apos;s no &quot;Friends Only&quot; tier - WoW Forever Tracker doesn&apos;t have a friends/following
            list to key one off (the Friends page browses everyone, it isn&apos;t a list you add people to).
          </p>
        </div>
        <div className="mt-3 flex flex-col gap-2 border-t border-neutral-700 pt-3 text-sm">
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={settings.show_playtime}
              onChange={(e) => setSettings({ ...settings, show_playtime: e.target.checked })}
            />
            Show total playtime on my account page
          </label>
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={settings.show_activity}
              onChange={(e) => setSettings({ ...settings, show_activity: e.target.checked })}
            />
            Show my activity in the global Activity feed
          </label>
        </div>
      </section>

      {/* CHARACTERS */}
      <section className="mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
        <h2 className="text-lg">Characters</h2>
        {characters.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">No characters synced yet.</p>
        ) : (
          <div className="mt-3 flex flex-col gap-3">
            {characters.map((c) => (
              <div key={c.id} className="flex flex-wrap items-center justify-between gap-2 rounded border border-neutral-700 bg-neutral-900/50 px-3 py-2">
                <span className="text-sm font-semibold">{c.name}</span>
                <div className="flex flex-wrap gap-4 text-sm text-gray-300">
                  <label className="flex items-center gap-1.5">
                    <input
                      type="checkbox"
                      checked={c.hidden}
                      onChange={(e) => updateCharacter(c.id, { hidden: e.target.checked })}
                    />
                    Hide from everyone else
                  </label>
                  <label className="flex items-center gap-1.5">
                    <input
                      type="checkbox"
                      checked={c.include_in_statistics}
                      onChange={(e) => updateCharacter(c.id, { include_in_statistics: e.target.checked })}
                    />
                    Count in account statistics
                  </label>
                </div>
              </div>
            ))}
          </div>
        )}
        <p className="mt-3 text-xs text-gray-500">
          A hidden character is left out of your Account Overview, the Friends/Items/Crafting lists and
          Leaderboards - it still exists and still syncs, it&apos;s just not shown anywhere public.
        </p>
      </section>

      {/* NOTIFICATIONS */}
      <section className="mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
        <h2 className="text-lg">Notifications</h2>
        <p className="mt-1 text-xs text-gray-500">
          No email, no separate inbox - these just control which kinds of events get a highlighted look when you
          browse the Activity feed.
        </p>
        <div className="mt-3 flex flex-col gap-2 text-sm">
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={settings.notify_achievement_earned}
              onChange={(e) => setSettings({ ...settings, notify_achievement_earned: e.target.checked })}
            />
            Highlight character achievements earned
          </label>
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={settings.notify_account_achievement_earned}
              onChange={(e) => setSettings({ ...settings, notify_account_achievement_earned: e.target.checked })}
            />
            Highlight account achievements earned
          </label>
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={settings.notify_legacy_completed}
              onChange={(e) => setSettings({ ...settings, notify_legacy_completed: e.target.checked })}
            />
            Highlight Legacy Challenges completed
          </label>
        </div>
      </section>

      <div className="mt-5 flex items-center gap-3">
        <button
          type="button"
          onClick={save}
          disabled={saving}
          className="rounded bg-blue-600 px-4 py-2 text-sm font-semibold disabled:opacity-50"
        >
          {saving ? "Saving..." : "Save Changes"}
        </button>
        {message && <span className="text-sm text-gray-400">{message}</span>}
      </div>
    </main>
  );
}