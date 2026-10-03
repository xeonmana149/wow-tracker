"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { supabase } from "../../../../lib/supabase";
import {
  exportAccountData,
  restoreFromExport,
  resetProfileCustomization,
  deleteAccountData,
} from "../../../../lib/accountExport";

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
  const router = useRouter();

  const [loading, setLoading] = useState(true);
  const [isOwner, setIsOwner] = useState(false);
  const [characters, setCharacters] = useState<CharacterRow[]>([]);
  const [settings, setSettings] = useState<ProfileSettings | null>(null);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");

  // Account Management (2026-10-03) - a separate message/busy state from the
  // Save Changes button above, since these actions (export/import/reset/
  // delete) aren't part of that form and can run independently of it.
  const [exporting, setExporting] = useState(false);
  const [importing, setImporting] = useState(false);
  const [resetting, setResetting] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [manageMessage, setManageMessage] = useState("");
  const importInputRef = useRef<HTMLInputElement | null>(null);
  const [deleteConfirmText, setDeleteConfirmText] = useState("");
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

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

  async function handleExport() {
    setExporting(true);
    setManageMessage("");
    try {
      const data = await exportAccountData(supabase, userId);
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      const datePart = new Date().toISOString().slice(0, 10);
      a.href = url;
      a.download = `wow-forever-export-${datePart}.json`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      setManageMessage("Downloaded.");
    } catch (err) {
      setManageMessage(err instanceof Error ? err.message : "Export failed.");
    } finally {
      setExporting(false);
    }
  }

  function handleImportClick() {
    importInputRef.current?.click();
  }

  async function handleImportFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = ""; // allow re-selecting the same file next time
    if (!file) return;
    setImporting(true);
    setManageMessage("");
    try {
      const text = await file.text();
      const parsed = JSON.parse(text);
      const result = await restoreFromExport(supabase, userId, parsed);
      setManageMessage(result.message);
      if (result.ok) {
        // Settings/characters state on screen may now be stale (restored
        // values came from the file, not from re-fetching) - reload so what's
        // shown matches what's actually saved.
        router.refresh();
        window.location.reload();
      }
    } catch {
      setManageMessage("Couldn't read that file - make sure it's a WoW Forever Tracker export (.json).");
    } finally {
      setImporting(false);
    }
  }

  async function handleResetCustomization() {
    if (!window.confirm("Reset your display name, avatar, banner, motto and Showcase picks back to default?")) return;
    setResetting(true);
    setManageMessage("");
    const result = await resetProfileCustomization(supabase, userId);
    setManageMessage(result.message);
    setResetting(false);
    if (result.ok) window.location.reload();
  }

  async function handleDeleteAccount() {
    if (deleteConfirmText !== "DELETE") return;
    setDeleting(true);
    setManageMessage("");
    const result = await deleteAccountData(supabase, userId);
    setDeleting(false);
    if (result.ok) {
      setShowDeleteConfirm(false);
      setDeleteConfirmText("");
      router.push(`/account/${userId}`);
      window.location.reload();
    } else {
      setManageMessage(result.message);
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

      {/* ACCOUNT MANAGEMENT (2026-10-03) */}
      <section className="mt-4 rounded-md border border-neutral-700 bg-neutral-800 p-4">
        <h2 className="text-lg">Account Management</h2>

        <div className="mt-3 flex flex-col gap-4 text-sm">
          <div>
            <p className="font-semibold text-gray-200">Export tracker data</p>
            <p className="mt-0.5 text-xs text-gray-500">
              Downloads a JSON file with everything on your account - profile, characters, gear, stats,
              achievements and Legacy Challenge progress.
            </p>
            <button
              type="button"
              onClick={handleExport}
              disabled={exporting}
              className="mt-2 rounded border border-neutral-600 px-3 py-1.5 text-sm hover:bg-neutral-700 disabled:opacity-50"
            >
              {exporting ? "Preparing..." : "Download my data"}
            </button>
          </div>

          <div className="border-t border-neutral-700 pt-3">
            <p className="font-semibold text-gray-200">Import data</p>
            <p className="mt-0.5 text-xs text-gray-500">
              Restores your profile, settings, hidden-character flags and achievement/Legacy Challenge progress
              from a file this Export produced. It won&apos;t touch gear, stats, professions, talents or your
              wishlist - re-sync the addon/tray app for those.
            </p>
            <input
              ref={importInputRef}
              type="file"
              accept="application/json"
              onChange={handleImportFile}
              className="hidden"
            />
            <button
              type="button"
              onClick={handleImportClick}
              disabled={importing}
              className="mt-2 rounded border border-neutral-600 px-3 py-1.5 text-sm hover:bg-neutral-700 disabled:opacity-50"
            >
              {importing ? "Restoring..." : "Restore from file..."}
            </button>
          </div>

          <div className="border-t border-neutral-700 pt-3">
            <p className="font-semibold text-gray-200">Reset profile customisation</p>
            <p className="mt-0.5 text-xs text-gray-500">
              Clears your display name, avatar, banner, motto and Showcase picks back to default. Characters,
              stats and achievements aren&apos;t affected.
            </p>
            <button
              type="button"
              onClick={handleResetCustomization}
              disabled={resetting}
              className="mt-2 rounded border border-neutral-600 px-3 py-1.5 text-sm hover:bg-neutral-700 disabled:opacity-50"
            >
              {resetting ? "Resetting..." : "Reset customisation"}
            </button>
          </div>

          <div className="border-t border-red-900/50 pt-3">
            <p className="font-semibold text-red-400">Delete tracker account</p>
            <p className="mt-0.5 text-xs text-gray-500">
              Permanently deletes your characters, gear, stats, achievements and Legacy Challenge progress, and
              resets your profile. This can&apos;t be undone. Your login isn&apos;t deleted - you can sync again
              anytime to start fresh.
            </p>
            {!showDeleteConfirm ? (
              <button
                type="button"
                onClick={() => setShowDeleteConfirm(true)}
                className="mt-2 rounded border border-red-700 px-3 py-1.5 text-sm text-red-400 hover:bg-red-950/40"
              >
                Delete my tracker data
              </button>
            ) : (
              <div className="mt-2 flex flex-col gap-2 rounded border border-red-800 bg-red-950/20 p-3">
                <p className="text-xs text-gray-300">
                  Type <span className="font-mono font-semibold text-red-400">DELETE</span> to confirm. This
                  can&apos;t be undone.
                </p>
                <input
                  type="text"
                  value={deleteConfirmText}
                  onChange={(e) => setDeleteConfirmText(e.target.value)}
                  className="w-40 rounded border border-neutral-700 bg-neutral-900 px-2 py-1 text-sm"
                  placeholder="DELETE"
                />
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={handleDeleteAccount}
                    disabled={deleteConfirmText !== "DELETE" || deleting}
                    className="rounded bg-red-700 px-3 py-1.5 text-sm font-semibold disabled:opacity-40"
                  >
                    {deleting ? "Deleting..." : "Permanently delete"}
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setShowDeleteConfirm(false);
                      setDeleteConfirmText("");
                    }}
                    className="rounded border border-neutral-600 px-3 py-1.5 text-sm hover:bg-neutral-700"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            )}
          </div>

          {manageMessage && <p className="text-xs text-gray-400">{manageMessage}</p>}
        </div>
      </section>
    </main>
  );
}