import Link from "next/link";
import AuthStatus from "../AuthStatus";
import Roadmap from "../Roadmap";
import { loadNews } from "../../lib/news";
import { loadBluePosts, type BluePost } from "../../lib/blueTracker";

// 2026-10-03 ("I like the news page how it is just remove all wow news
// button, the official blizzard news button and the beta announcement
// button and add a tab to see blue posts specifically for wow forever") -
// the page keeps its existing look (same "WoW Forever" Wowhead-news feed,
// same card layout) and loses its three link-out buttons (the "All WoW
// news" toggle, and the two external "↗" links to Blizzard's own site),
// replaced with one new tab sourced from Wowhead's Forever-specific Blue
// Tracker (see lib/blueTracker.ts) - official posts from Blizzard
// developers/community managers, already filtered to just this game by
// Wowhead itself.
function timeAgo(date: Date | null) {
  if (!date) return "";
  const mins = Math.round((Date.now() - date.getTime()) / 60000);
  if (mins < 60) return `${Math.max(1, mins)} min ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} hr ago`;
  const days = Math.round(hours / 24);
  return days === 1 ? "1 day ago" : `${days} days ago`;
}

function BluePostCard({ post }: { post: BluePost }) {
  const isNews = post.kind === "news";
  return (
    <Link href={post.link} target="_blank" rel="noopener noreferrer" className="news-card">
      <div className="flex flex-1 flex-col gap-2 p-4">
        <div className="flex flex-wrap items-center gap-2 text-xs text-gray-400">
          {/* Gold for official Blizzard News, blue for a forum/blue post -
              reuses the existing .chip/.chip-alliance styles (the same blue
              already used elsewhere on the site for Alliance), rather than
              introducing new CSS just for this. */}
          <span className={`chip ${!isNews ? "chip-alliance" : ""}`}>
            {isNews ? "🟡 BLIZZARD NEWS" : "🔵 BLUE POST"}
          </span>
          {post.category && <span className="chip">{post.category}</span>}
        </div>
        <h2 className="news-title text-lg font-bold">{post.title}</h2>
        <p className="text-xs text-gray-500">
          {post.author && <>{post.author} · </>}
          {timeAgo(post.date)}
        </p>
        {post.excerpt && <p className="line-clamp-3 text-sm text-gray-400">{post.excerpt}</p>}
        <span className="mt-auto pt-1 text-sm text-blue-400">Read post ↗</span>
      </div>
    </Link>
  );
}

export default async function News({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string }>;
}) {
  const { tab } = await searchParams;
  const showBlue = tab === "blue";

  const all = showBlue ? null : await loadNews();
  const bluePosts = showBlue ? await loadBluePosts() : null;

  const items = (all ?? [])
    .filter((i) => i.category === "Forever" || /forever/i.test(i.title))
    .slice(0, 24);

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <AuthStatus />

      <h1 className="text-3xl font-bold">News</h1>
      <div className="mt-5">
        <Roadmap />
      </div>

      <div className="mt-5 flex flex-wrap gap-2">
        <Link href="/news" className={`nav-btn ${!showBlue ? "nav-btn-active" : ""}`}>
          WoW Forever
        </Link>
        <Link href="/news?tab=blue" className={`nav-btn ${showBlue ? "nav-btn-active" : ""}`}>
          Blue Posts
        </Link>
      </div>

      {!showBlue && all === null && (
        <div className="mt-6 rounded bg-neutral-800 p-4">
          <p>The news list couldn&apos;t be loaded right now.</p>
          <p className="mt-2 text-sm text-gray-400">It will try again in a few minutes.</p>
        </div>
      )}
      {!showBlue && all !== null && items.length === 0 && (
        <p className="mt-6 text-gray-400">No stories to show yet.</p>
      )}

      {showBlue && bluePosts === null && (
        <div className="mt-6 rounded bg-neutral-800 p-4">
          <p>Blue posts couldn&apos;t be loaded right now.</p>
          <p className="mt-2 text-sm text-gray-400">
            It will try again in a few minutes. In the meantime, the full tracker is at{" "}
            <Link
              href="https://www.wowhead.com/forever/blue-tracker"
              target="_blank"
              rel="noopener noreferrer"
              className="text-blue-400 underline"
            >
              Wowhead&apos;s Forever Blue Tracker
            </Link>
            .
          </p>
        </div>
      )}
      {showBlue && bluePosts !== null && bluePosts.length === 0 && (
        <p className="mt-6 text-gray-400">No blue posts to show yet.</p>
      )}

      <div className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {!showBlue &&
          items.map((item) => (
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

        {showBlue &&
          (bluePosts ?? []).map((post) => <BluePostCard key={post.link} post={post} />)}
      </div>

      <p className="mt-8 text-xs text-gray-500">
        {showBlue
          ? "Blue posts via Wowhead's WoW Forever Blue Tracker. \"Read post\" opens the original source. The list refreshes about every 15 minutes."
          : "Headlines come from Wowhead's news feed, which covers Blizzard's announcements and blue posts. The full stories are on their site. The list refreshes about every 15 minutes."}
      </p>
    </main>
  );
}