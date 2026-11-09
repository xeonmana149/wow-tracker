import Link from "next/link";
import { supabaseAdmin } from "../../../lib/supabaseAdmin";
import { LATEST_VERSIONS } from "../../../lib/versions";
import { formatDate } from "../../../lib/accountView";

// Who's on which version (2026-11-09, "a way to check what version app and
// addon my friends have installed so I can always make sure they are up
// to date"). Every account with its addon and tray app version, against
// the current release in lib/versions.ts, plus when it last synced.
//
// The versions are what each account's syncs have reported - the sync
// route keeps the newest one seen (app/api/sync/route.ts), so an account
// that hasn't synced since an update still shows the old one. Like
// /dev/badges, nothing links here; visit /dev/versions directly.
export const dynamic = "force-dynamic";

type Profile = { id: string; display_name: string | null; addon_version: string | null; tray_version: string | null };

function VersionCell({ have, latest }: { have: string | null; latest: string }) {
  if (!have) return <span className="text-gray-500">never reported</span>;
  const ok = have === latest;
  return (
    <span className={ok ? "text-green-400" : "font-semibold text-red-400"}>
      {have}
      {ok ? " ✓" : ` → needs ${latest}`}
    </span>
  );
}

export default async function VersionsPage() {
  const [{ data: profiles }, { data: chars }, { data: stats }] = await Promise.all([
    supabaseAdmin.from("profiles").select("id, display_name, addon_version, tray_version").order("display_name"),
    supabaseAdmin.from("characters").select("user_id, name"),
    // Statistics are rewritten on every sync - their newest time is the
    // account's last sync
    supabaseAdmin.from("character_statistics").select("user_id, updated_at").order("updated_at", { ascending: false }),
  ]);

  const lastSync = new Map<string, string>();
  for (const s of (stats ?? []) as { user_id: string; updated_at: string }[]) {
    if (!lastSync.has(s.user_id)) lastSync.set(s.user_id, s.updated_at);
  }
  const charNames = new Map<string, string[]>();
  for (const c of (chars ?? []) as { user_id: string; name: string }[]) {
    charNames.set(c.user_id, [...(charNames.get(c.user_id) ?? []), c.name]);
  }
  const rows = ((profiles ?? []) as Profile[]).filter((p) => charNames.has(p.id) || p.addon_version || p.tray_version);
  const behind = rows.filter(
    (p) => p.addon_version !== LATEST_VERSIONS.addon || p.tray_version !== LATEST_VERSIONS.tray
  ).length;

  return (
    <main className="mx-auto max-w-4xl p-4 text-white md:p-6">
      <h1 className="text-2xl font-bold">Versions</h1>
      <p className="mt-1 text-sm text-gray-400">
        Latest: addon <span className="text-white">{LATEST_VERSIONS.addon}</span>, app{" "}
        <span className="text-white">{LATEST_VERSIONS.tray}</span>.{" "}
        {behind === 0 ? "Everyone is up to date." : `${behind} of ${rows.length} accounts are behind.`}
      </p>

      <div className="mt-4 overflow-x-auto rounded border border-neutral-700">
        <table className="w-full text-left text-sm">
          <thead className="bg-neutral-900 text-xs text-gray-400">
            <tr>
              <th className="px-3 py-2">Account</th>
              <th className="px-3 py-2">Characters</th>
              <th className="px-3 py-2">Addon</th>
              <th className="px-3 py-2">App</th>
              <th className="px-3 py-2">Last sync</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((p) => (
              <tr key={p.id} className="border-t border-neutral-800">
                <td className="px-3 py-2">
                  <Link href={`/account/${p.id}`} className="font-semibold hover:underline">
                    {p.display_name ?? "Unknown"}
                  </Link>
                </td>
                <td className="px-3 py-2 text-gray-300">{(charNames.get(p.id) ?? []).join(", ") || "-"}</td>
                <td className="px-3 py-2">
                  <VersionCell have={p.addon_version} latest={LATEST_VERSIONS.addon} />
                </td>
                <td className="px-3 py-2">
                  <VersionCell have={p.tray_version} latest={LATEST_VERSIONS.tray} />
                </td>
                <td className="px-3 py-2 text-gray-400">
                  {lastSync.has(p.id) ? formatDate(lastSync.get(p.id) as string) : "never"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </main>
  );
}
