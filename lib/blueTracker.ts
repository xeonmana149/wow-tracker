// WoW Forever Blue Tracker (2026-10-03, "add a tab to see blue posts
// specifically for wow forever") - sources from Wowhead's own Forever-scoped
// Blue Tracker, which already separates official Blizzard News from
// community-manager/dev forum posts for just this one game, so the News page
// doesn't need to do any of that filtering itself. Same shape as lib/news.ts
// (shared FEED/REVALIDATE_SECONDS constants, fetched with next.revalidate so
// the News page and the /api/refresh-news warm-up ping share one cache
// entry) - kept in its own module, deliberately, so a future Wowhead markup
// change only ever needs fixing in one place.
//
// IMPORTANT CAVEAT: Wowhead doesn't publish a documented API for this feed.
// The URL below is the RSS link Wowhead's own page advertises for the
// Forever Blue Tracker (https://www.wowhead.com/forever/blue-tracker), found
// by inspecting that page's HTML - not confirmed against a real fetched
// response in this environment (this sandbox's outbound network is
// allowlisted to package registries/GitHub only, so wowhead.com can't
// actually be reached from here to verify the feed's real tag names). The
// parser below is written defensively - it tries a few plausible tag names
// for "author" and "post type" and simply omits a field it can't find rather
// than throwing - but if the Blue Posts tab comes back empty or looks wrong
// once this is live on the real site, the fix is almost certainly here:
// paste one raw <item>...</item> block from a real response (view-source on
// https://www.wowhead.com/forever/blue-tracker?rss) and this parser can be
// corrected against real data in minutes.
export const BLUE_TRACKER_FEED = "https://www.wowhead.com/forever/blue-tracker?rss";
export const BLUE_TRACKER_REVALIDATE_SECONDS = 900;

export type BluePost = {
  title: string;
  link: string;
  author: string;
  category: string;
  // "news" = an official Blizzard News post, "forum" = a blue/community-
  // manager forum post - the small indicator dot and chip color on each
  // card depend on this (see news-page/page.tsx).
  kind: "news" | "forum";
  excerpt: string;
  date: Date | null;
};

function decode(s: string) {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;|&#x27;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&amp;/g, "&");
}

function tag(chunk: string, name: string) {
  const m = chunk.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`));
  return m ? m[1].replace(/^<!\[CDATA\[|\]\]>$/g, "").trim() : "";
}

// Tries each candidate tag name in order and returns the first one that
// actually has content - different RSS generators call the "who wrote this"
// field different things (plain <author>, the more common <dc:creator> used
// by WordPress/community-forum feeds, or sometimes it's folded into
// <creator>). Wowhead's general news feed (lib/news.ts) doesn't need this at
// all since Blizzard/Wowhead staff bylines aren't in that feed - the blue
// tracker is different in that the whole point is surfacing WHICH Blizzard
// person posted, so this is worth trying several names for rather than
// giving up after one.
function firstTag(chunk: string, names: string[]) {
  for (const name of names) {
    const value = decode(tag(chunk, name));
    if (value) return value;
  }
  return "";
}

// Heuristic only (see the module header caveat) - an explicit <category>
// of "News"/"Blizzard News" (or an author of "Blizzard Entertainment", the
// byline Blizzard's own news posts use) means this is an official news
// article; everything else is a forum/blue post, which matches how the
// mockup in the 2026-10-03 request tells the two apart (gold "BLIZZARD NEWS"
// vs blue "BLUE POST").
function classify(category: string, author: string): "news" | "forum" {
  if (/\bnews\b/i.test(category) || /blizzard entertainment/i.test(author)) return "news";
  return "forum";
}

function parseFeed(xml: string): BluePost[] {
  const posts: BluePost[] = [];

  for (const chunk of xml.split("<item>").slice(1)) {
    const title = decode(tag(chunk, "title"));
    const link = tag(chunk, "link");
    if (!title || !link.startsWith("https://")) continue;

    const rawExcerpt = tag(chunk, "description").split("&lt;br&gt;")[0];
    const excerpt = decode(rawExcerpt).replace(/<[^>]+>/g, "").trim();

    const author = firstTag(chunk, ["dc:creator", "author", "creator"]);
    const category = decode(tag(chunk, "category"));
    const time = Date.parse(tag(chunk, "pubDate"));

    posts.push({
      title,
      link,
      author,
      category,
      kind: classify(category, author),
      excerpt,
      date: Number.isNaN(time) ? null : new Date(time),
    });
  }

  return posts;
}

// Fetched at most once every BLUE_TRACKER_REVALIDATE_SECONDS, however many
// people (or scheduled pings) call this - same dedupe-on-url+options
// behavior as loadNews() in lib/news.ts.
export async function loadBluePosts(): Promise<BluePost[] | null> {
  try {
    const res = await fetch(BLUE_TRACKER_FEED, {
      headers: { "User-Agent": "WoWForeverTracker/1.0 (private friends planner)" },
      next: { revalidate: BLUE_TRACKER_REVALIDATE_SECONDS },
    });
    if (!res.ok) return null;
    return parseFeed(await res.text());
  } catch {
    return null;
  }
}
