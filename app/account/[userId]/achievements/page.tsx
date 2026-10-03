import Link from "next/link";
import { supabaseAdmin } from "../../../../lib/supabaseAdmin";
import { loadAccountViewData } from "../../../../lib/accountView";
import AccountBadgesGrid from "../../../AccountBadgesGrid";
import AccountAchievementsTabs from "./AccountAchievementsTabs";

// Account Achievements (2026-10-03, the "Achievements" tab that's sat
// disabled/"Coming soon" on the Account Overview page since the 2026-09-28
// layout rework - see AccountView.tsx) - an Account Achievements area (the
// same AccountBadgesGrid already shown on the Overview page) plus a tab per
// character for that character's own full achievement browser. A plain
// server component fetching with supabaseAdmin, same reasoning as the
// Statistics/Activity pages and the public /account/[userId] overview
// itself: this needs to work when viewing ANY account, not just your own.
export default async function AccountAchievementsPage({ params }: { params: Promise<{ userId: string }> }) {
  const { userId } = await params;

  const { data: profileRow } = await supabaseAdmin.from("profiles").select("display_name").eq("id", userId).maybeSingle();
  const data = await loadAccountViewData(supabaseAdmin, userId, null);

  return (
    <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">{profileRow?.display_name ?? "Account"}&apos;s Achievements</h1>
          <p className="mt-1 text-sm text-gray-400">Account-wide achievements, plus each character&apos;s own trophy cabinet.</p>
        </div>
        <Link href={`/account/${userId}`} className="text-xs text-amber-400 hover:underline">
          ← Back to Account
        </Link>
      </div>

      <div className="mt-6 rounded-md border border-neutral-700 bg-neutral-800 p-4">
        <h2 className="text-lg">Account Achievements</h2>
        <AccountBadgesGrid
          accountBadges={data.accountBadges}
          accountBadgeProgress={data.accountBadgeProgress}
          accountBadgeBreakdown={data.accountBadgeBreakdown}
          iconOverrides={data.iconOverrides}
        />
      </div>

      {data.characters.length === 0 ? (
        <p className="mt-6 text-sm text-gray-500">No characters synced yet.</p>
      ) : (
        <div className="mt-6">
          <h2 className="text-lg">Character Achievements</h2>
          <AccountAchievementsTabs characters={data.characters} mainCharacterId={data.mainCharacter?.id ?? null} />
        </div>
      )}
    </main>
  );
}
