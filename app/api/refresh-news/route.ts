import { NextResponse } from "next/server";
import { loadNews } from "../../../lib/news";
import { loadBluePosts } from "../../../lib/blueTracker";

// A ping target for an external scheduler (a free cron pinger, or a GitHub
// Actions scheduled workflow) to hit every 10-15 minutes. Next.js only
// re-fetches a cached URL when something actually requests the page that
// calls it - with no traffic, the News page would just keep showing
// whatever it last fetched, however old that gets. This route calls the
// exact same fetch() calls the News page itself does (same URLs, same
// revalidate windows, from lib/news.ts and lib/blueTracker.ts) so hitting
// THIS endpoint on a schedule keeps both shared cache entries warm, and
// real visitors always get freshly-refreshed content instead of whatever
// was cached at their last visit.
//
// 2026-10-03 ("add a tab to see blue posts specifically for wow forever") -
// extended to also warm the new Blue Tracker feed, rather than standing up
// a second scheduled ping just for it - whatever's already pinging this
// route (see the comment above) keeps both tabs fresh with no extra setup.
export async function GET() {
  const [news, bluePosts] = await Promise.all([loadNews(), loadBluePosts()]);
  return NextResponse.json({
    ok: news !== null && bluePosts !== null,
    newsCount: news?.length ?? 0,
    bluePostsCount: bluePosts?.length ?? 0,
  });
}