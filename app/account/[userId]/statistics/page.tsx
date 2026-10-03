import Link from "next/link";
import { supabaseAdmin } from "../../../../lib/supabaseAdmin";
import { loadAccountStatisticsData } from "../../../../lib/accountStatistics";
import StatisticsTabs from "./StatisticsTabs";

// Account Statistics (2026-10-03, "Statistics should go to a tab with
// account-wide statistics plus an area with all character statistics but
// they are like in their own tab to not overload info") - a plain server
// component fetching with supabaseAdmin, same reasoning as the public
// /account/[userId] overview page itself: this needs to work for viewing
// ANY account's statistics (not just your own), and RLS on
// characters/character_statistics only lets a signed-in user read their own
// rows otherwise.
export default async function AccountStatisticsPage({ params }: { params: Promise<{ userId: string }> }) {
  const { userId } = await params;

  const { data: profileRow } = await supabaseAdmin.from("profiles").select("display_name").eq("id", userId).maybeSingle();
  const data = await loadAccountStatisticsData(supabaseAdmin, userId);

  return (
    <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">{profileRow?.display_name ?? "Account"}&apos;s Statistics</h1>
          <p className="mt-1 text-sm text-gray-400">Account-wide totals, plus each character&apos;s own statistics.</p>
        </div>
        <Link href={`/account/${userId}`} className="text-xs text-amber-400 hover:underline">
          ← Back to Account
        </Link>
      </div>

      {data.characters.length === 0 ? (
        <p className="mt-6 text-sm text-gray-500">No characters synced yet.</p>
      ) : (
        <StatisticsTabs characters={data.characters} statsByCharacter={data.statsByCharacter} aggregated={data.aggregated} />
      )}
    </main>
  );
}
