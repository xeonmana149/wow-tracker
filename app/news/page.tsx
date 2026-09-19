import Link from "next/link";
import AuthStatus from "../AuthStatus";
import Roadmap from "../Roadmap";

const FEED = "https://www.wowhead.com/news/rss/all";
const BLIZZARD_NEWS = "https://news.blizzard.com/en-us/world-of-warcraft";
const BETA_POST =
  "https://news.blizzard.com/en-us/article/24304160/the-world-of-warcraft-forever-beta-now-live";

// As announced by Blizzard: 4 November, 3:00 p.m. PST


type NewsItem = {
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

// Fetched at most once every 15 minutes, however many people visit
async function loadNews(): Promise<NewsItem[] | null> {
  try {
    const res = await fetch(FEED, {
      headers: { "User-Agent": "WoWForeverTracker/1.0 (private friends planner)" },
      next: { revalidate: 900 },
    });
    if (!res.ok) return null;
    return parseFeed(await res.text());
  } catch {
    return null;
  }
}

function timeAgo(date: Date | null) {
  if (!date) return "";
  const mins = Math.round((Date.now() - date.getTime()) / 60000);
  if (mins < 60) return `${Math.max(1, mins)} min ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} hr ago`;
  const days = Math.round(hours / 24);
  return days === 1 ? "1 day ago" : `${days} days ago`;
}

export default async function News({
  searchParams,
}: {
  searchParams: Promise<{ show?: string }>;
}) {
  const { show } = await searchParams;
  const showAll = show === "all";

  const all = await loadNews();
  const items = (all ?? [])
    .filter((i) => showAll || i.category === "Forever" || /forever/i.test(i.title))
    .slice(0, 24);


  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <AuthStatus />

      <h1 className="text-3xl font-bold">News</h1>
      <div className="mt-5">
        <Roadmap />
      </div>

      <div className="mt-5 flex flex-wrap gap-2">
        <Link href="/news" className={`nav-btn ${!showAll ? "nav-btn-active" : ""}`}>
          WoW Forever
        </Link>
        <Link href="/news?show=all" className={`nav-btn ${showAll ? "nav-btn-active" : ""}`}>
          All WoW news
        </Link>
        <Link
          href={BLIZZARD_NEWS}
          target="_blank"
          rel="noopener noreferrer"
          className="nav-btn ml-auto"
        >
          Official Blizzard news ↗
        </Link>
        <Link href={BETA_POST} target="_blank" rel="noopener noreferrer" className="nav-btn">
          Beta announcement ↗
        </Link>
      </div>

      {all === null && (
        <div className="mt-6 rounded bg-neutral-800 p-4">
          <p>The news list couldn&apos;t be loaded right now.</p>
          <p className="mt-2 text-sm text-gray-400">
            It will try again in a few minutes. In the meantime, the official page has
            everything:{" "}
            <Link
              href={BLIZZARD_NEWS}
              target="_blank"
              rel="noopener noreferrer"
              className="text-blue-400 underline"
            >
              Blizzard&apos;s World of Warcraft news
            </Link>
            .
          </p>
        </div>
      )}

      {all !== null && items.length === 0 && (
        <p className="mt-6 text-gray-400">No stories to show yet.</p>
      )}

      <div className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {items.map((item) => (
          <Link
            key={item.link}
            href={item.link}
            target="_blank"
            rel="noopener noreferrer"
            className="news-card"
          >
            {item.image && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={item.image} alt="" loading="lazy" />
            )}
            <div className="flex flex-1 flex-col gap-2 p-4">
              <div className="flex items-center gap-2 text-xs text-gray-400">
                {item.category && <span className="chip">{item.category}</span>}
                <span>{timeAgo(item.date)}</span>
              </div>
              <h2 className="news-title text-lg font-bold">{item.title}</h2>
              {item.summary && (
                <p className="line-clamp-3 text-sm text-gray-400">{item.summary}</p>
              )}
              <span className="mt-auto pt-1 text-sm text-blue-400">Read the full story ↗</span>
            </div>
          </Link>
        ))}
      </div>

      <p className="mt-8 text-xs text-gray-500">
        Headlines come from Wowhead&apos;s news feed, which covers Blizzard&apos;s announcements
        and blue posts. The full stories are on their site, and Blizzard&apos;s own posts are on
        news.blizzard.com. The list refreshes about every 15 minutes.
      </p>
    </main>
  );
}