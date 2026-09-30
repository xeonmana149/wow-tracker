import Link from "next/link";
import { supabaseAdmin } from "../../../lib/supabaseAdmin";
import { loadAccountViewData } from "../../../lib/accountView";
import { AccountView } from "../../AccountView";

// Public account view (2026-09-30, answering "how do we see other players
// account pages?") - a read-only look at ANY player's account overview by
// their user id, no Edit Profile button or panel (see AccountView.tsx,
// which is the exact same display /account/page.tsx uses for your own
// account, just with those slots left empty here).
//
// This is a plain server component (no "use client") rather than a fetch-
// on-mount client page: it has nothing interactive to do, and fetching with
// supabaseAdmin only works server-side anyway (the service-role key must
// never reach the browser). supabaseAdmin bypasses RLS on purpose - RLS on
// `characters`/`achievements`/etc. otherwise only lets a signed-in user read
// their OWN rows (see ItemSearch.tsx's character list), which is exactly
// why this page couldn't just reuse the browser `supabase` client the way
// the owner's own /account page does.
//
// Not yet wired up: no link anywhere on the site points here yet (Friends,
// Leaderboards, and search results are the natural places) - that's the
// next step once this page itself is confirmed working.

export default async function PublicAccountPage({ params }: { params: Promise<{ userId: string }> }) {
  // Next.js 15+ made dynamic route `params` a Promise (previously a plain
  // object) - awaiting it here works either way, since awaiting a value
  // that's already a plain object just resolves to that object unchanged.
  // (2026-09-30: without this, `userId` was the unresolved Promise itself,
  // not the actual id string, which is why supabase-js's admin API
  // rejected it with "Expected parameter to be UUID but is not".)
  const { userId } = await params;

  const { data: authUser } = await supabaseAdmin.auth.admin.getUserById(userId);
  const data = await loadAccountViewData(supabaseAdmin, userId, authUser?.user?.created_at ?? null);

  if (!data.found) {
    return (
      <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
        <h1 className="text-3xl font-bold">Account not found</h1>
        <p className="mt-4 text-sm text-gray-400">
          There's no account here.{" "}
          <Link href="/" className="text-amber-400 hover:underline">
            Back to Dashboard
          </Link>
        </p>
      </main>
    );
  }

  return <AccountView data={data} />;
}