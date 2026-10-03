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

// Pinned changelog post (2026-10-03, "this is the main changelog for
// updates for the beta and when game launches I will change this to just
// game update change logs... we should pin it to that top bar so when the
// date changes users can see it") - Blizzard reuses the SAME blue post for
// this (just edits the date in its title each time, e.g. "Updated 1
// October" / "Updated October 1"), so rather than treating it as one more
// item in the list, the News page pulls out whichever post matches this
// title pattern and pins it in its own banner above both tabs.
//
// This is the one thing in this file that's expected to need editing by
// hand later, not from a feed-format change but from Jordan's own plan: once
// the game launches and these become "game update change logs" instead of
// "Beta Development Notes", update this pattern to match the new title
// (e.g. /change log/i or /patch notes/i) - everything else (pickPinnedPost,
// the banner in news-page/page.tsx) keeps working unchanged.
export const PINNED_POST_TITLE_PATTERN = /development notes/i;

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

// De-dupe key for one post (2026-10-03, "it does give some duplicates") -
// Blizzard cross-posts the same blue post to both the US and EU forums, and
// Wowhead's combined Forever tracker surfaces both as separate items with
// different links (…/topic/us/… vs …/topic/eu/…). Their TITLES can differ
// too when the post embeds a date, since US and EU phrase a date
// differently ("Updated 1 October" vs "Updated October 1" - the exact
// "Beta Development Notes" pair this request called out) - so title isn't a
// reliable de-dupe key on its own. The post BODY (excerpt) is copy-pasted
// identically to both regions' forums, so that's what this keys on when
// there's enough of it to be meaningful; a title with any trailing
// "- Updated <date>"-style clause and punctuation stripped out is the
// fallback for the rare post with no excerpt at all.
function dedupeKey(post: BluePost): string {
  const excerptKey = post.excerpt.toLowerCase().replace(/\s+/g, " ").trim().slice(0, 140);
  if (excerptKey.length >= 20) return excerptKey;
  return post.title
    .toLowerCase()
    .replace(/[-–]\s*updated\b.*$/i, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

// Keeps the first post seen for each de-dupe key - callers sort newest-first
// before calling this, so "first seen" is also "most recent of the pair".
function dedupe(posts: BluePost[]): BluePost[] {
  const seen = new Set<string>();
  const result: BluePost[] = [];
  for (const post of posts) {
    const key = dedupeKey(post);
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(post);
  }
  return result;
}

function sortByDateDesc(posts: BluePost[]): BluePost[] {
  return [...posts].sort((a, b) => (b.date?.getTime() ?? 0) - (a.date?.getTime() ?? 0));
}

// Fetched at most once every BLUE_TRACKER_REVALIDATE_SECONDS, however many
// people (or scheduled pings) call this - same dedupe-on-url+options
// behavior as loadNews() in lib/news.ts. Returned posts are newest-first and
// already de-duplicated across US/EU regional cross-posts.
export async function loadBluePosts(): Promise<BluePost[] | null> {
  try {
    const res = await fetch(BLUE_TRACKER_FEED, {
      headers: { "User-Agent": "WoWForeverTracker/1.0 (private friends planner)" },
      next: { revalidate: BLUE_TRACKER_REVALIDATE_SECONDS },
    });
    if (!res.ok) return null;
    return dedupe(sortByDateDesc(parseFeed(await res.text())));
  } catch {
    return null;
  }
}

// Finds the newest post matching PINNED_POST_TITLE_PATTERN (see its own
// comment above) so the News page can pin it in a banner instead of leaving
// it to show up (and get buried) as just another card in the list. `posts`
// is expected already sorted newest-first, as loadBluePosts() returns it, so
// the first match is the current one.
export function pickPinnedPost(posts: BluePost[]): BluePost | null {
  return posts.find((p) => PINNED_POST_TITLE_PATTERN.test(p.title)) ?? null;
}