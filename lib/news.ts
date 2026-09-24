// Shared by the News page and the /api/refresh-news warm-up endpoint - both
// need to call fetch() with the EXACT same URL and revalidate value for the
// warm-up ping to actually refresh the cache entry the page later reads.
// Next.js's fetch cache is keyed by the request (url + options), not by
// which route happened to call it.

export const FEED = "https://www.wowhead.com/news/rss/all";
export const REVALIDATE_SECONDS = 900;

export type NewsItem = {
  title: string;
  link: string;
  summary: string;
  category: string;
  image: string | null;
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

// The text inside one tag of a feed item
function tag(chunk: string, name: string) {
  const m = chunk.match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`));
  return m ? m[1].replace(/^<!\[CDATA\[|\]\]>$/g, "").trim() : "";
}

function parseFeed(xml: string): NewsItem[] {
  const items: NewsItem[] = [];

  for (const chunk of xml.split("<item>").slice(1)) {
    const title = decode(tag(chunk, "title"));
    const link = tag(chunk, "link");
    if (!title || !link.startsWith("https://")) continue;

    // The description starts with a one-line summary, then a "continue reading" link
    const rawSummary = tag(chunk, "description").split("&lt;br&gt;")[0];
    const summary = decode(rawSummary).replace(/<[^>]+>/g, "").trim();

    const time = Date.parse(tag(chunk, "pubDate"));
    const image = chunk.match(/<media:content[^>]*\burl="([^"]+)"/)?.[1] ?? null;

    items.push({
      title,
      link,
      summary,
      category: tag(chunk, "category"),
      image: image && image.startsWith("https://") ? image : null,
      date: Number.isNaN(time) ? null : new Date(time),
    });
  }

  return items;
}

// Fetched at most once every REVALIDATE_SECONDS, however many people (or
// scheduled pings) call this - Next.js's data cache dedupes on url+options.
export async function loadNews(): Promise<NewsItem[] | null> {
  try {
    const res = await fetch(FEED, {
      headers: { "User-Agent": "WoWForeverTracker/1.0 (private friends planner)" },
      next: { revalidate: REVALIDATE_SECONDS },
    });
    if (!res.ok) return null;
    return parseFeed(await res.text());
  } catch {
    return null;
  }
}