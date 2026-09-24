import { NextResponse } from "next/server";
import { loadNews } from "../../../lib/news";

// A ping target for an external scheduler (a free cron pinger, or a GitHub
// Actions scheduled workflow) to hit every 10-15 minutes. Next.js only
// re-fetches a cached URL when something actually requests the page that
// calls it - with no traffic, the News page would just keep showing
// whatever it last fetched, however old that gets. This route calls the
// exact same fetch() (same URL, same revalidate window, from lib/news.ts)
// so hitting THIS endpoint on a schedule keeps that shared cache entry
// warm, and real visitors then always get freshly-refreshed content
// instead of whatever was cached at their last visit.
export async function GET() {
  const items = await loadNews();
  return NextResponse.json({ ok: items !== null, count: items?.length ?? 0 });
}