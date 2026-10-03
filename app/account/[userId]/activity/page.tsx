import Link from "next/link";
import { supabaseAdmin } from "../../../../lib/supabaseAdmin";
import ActivityFeed from "./ActivityFeed";

// Account Activity (2026-10-03, "The activity button should be a page of
// all activity tracked on the website from its inception... Just an
// infinite long scrolldown maybe? So everyone can see all their history.") -
// feeds from the new shared `activity_log` table (sql/activity-log.sql),
// which only starts recording from the day it was created - there was never
// an existing log to backfill from, see that migration's own header comment.
// Plain server component just for the header/not-found check; the actual
// infinite-scroll list is ActivityFeed.tsx (needs hooks/state, so it's its
// own "use client" piece).
export default async function AccountActivityPage({ params }: { params: Promise<{ userId: string }> }) {
  const { userId } = await params;

  const { data: profileRow } = await supabaseAdmin.from("profiles").select("display_name").eq("id", userId).maybeSingle();

  return (
    <main className="mx-auto max-w-4xl p-4 text-white md:p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">{profileRow?.display_name ?? "Account"}&apos;s Activity</h1>
          <p className="mt-1 text-sm text-gray-400">Everything tracked on this account, newest first.</p>
        </div>
        <Link href={`/account/${userId}`} className="text-xs text-amber-400 hover:underline">
          ← Back to Account
        </Link>
      </div>

      <ActivityFeed userId={userId} />
    </main>
  );
}
