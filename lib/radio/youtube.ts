// Azeroth Radio: YouTube song links. A station plays YouTube videos only
// through YouTube's own embedded player, which listeners must be able to see
// while it plays (YouTube's rules: no hidden or background players). The only
// network call here is YouTube's public oEmbed endpoint, which says whether a
// video exists and may be embedded, plus its title, channel and thumbnail.

const ID = /^[A-Za-z0-9_-]{11}$/;
const HOSTS = new Set(["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com"]);

export type YouTubeLink = { ok: true; id: string } | { ok: false; error: string } | null;

// null: not a YouTube link at all.
export function parseYouTubeUrl(raw: unknown): YouTubeLink {
  if (typeof raw !== "string") return null;
  let text = raw.trim();
  if (/^(?:(?:www|m|music)\.)?youtube\.com\/|^youtu\.be\//i.test(text)) text = "https://" + text;
  let u: URL;
  try {
    u = new URL(text);
  } catch {
    return null;
  }
  const host = u.hostname.toLowerCase();
  if (host !== "youtu.be" && !HOSTS.has(host)) return null;
  if (u.protocol !== "https:" && u.protocol !== "http:") return { ok: false, error: "Only web links work here." };
  if (u.username || u.password || u.port) return { ok: false, error: "That link has extra parts YouTube links never have." };
  const parts = u.pathname.split("/").filter(Boolean);
  let id: string | null = null;
  if (host === "youtu.be") id = parts[0] ?? null;
  else if (parts[0] === "watch") id = u.searchParams.get("v");
  else if (["shorts", "embed", "live", "v"].includes(parts[0])) id = parts[1] ?? null;
  else if (parts[0] === "playlist") return { ok: false, error: "That's a YouTube playlist - request one song at a time." };
  if (!id) return { ok: false, error: "That YouTube link doesn't point at a video." };
  if (!ID.test(id)) return { ok: false, error: "That doesn't look like a YouTube video link." };
  return { ok: true, id };
}

export const youTubeWatchUrl = (id: string) => `https://www.youtube.com/watch?v=${id}`;

export function isYouTubeThumb(raw: unknown): raw is string {
  try {
    const u = new URL(String(raw));
    return u.protocol === "https:" && !u.port && /(^|\.)ytimg\.com$/i.test(u.hostname) && String(raw).length <= 500;
  } catch {
    return false;
  }
}

export type YouTubeInfo = { providerId: string; title: string; artist: string | null; permalink: string; artwork: string | null };

export async function lookUpYouTube(id: string): Promise<{ ok: true; track: YouTubeInfo } | { ok: false; error: string }> {
  const url = youTubeWatchUrl(id);
  let res: Response;
  try {
    res = await fetch(`https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(url)}`, {
      signal: AbortSignal.timeout(6000),
      headers: { Accept: "application/json" },
      cache: "no-store",
    });
  } catch {
    return { ok: false, error: "Couldn't reach YouTube to check that link. Try again in a moment." };
  }
  if (res.status === 401 || res.status === 403) return { ok: false, error: "That video's owner doesn't allow it to be played outside YouTube." };
  if (res.status === 404 || res.status === 400) return { ok: false, error: "YouTube can't find that video - it may be private or deleted." };
  if (!res.ok) return { ok: false, error: "YouTube couldn't check that link right now." };
  let body: { title?: string; author_name?: string; thumbnail_url?: string };
  try {
    body = await res.json();
  } catch {
    return { ok: false, error: "YouTube gave an answer we couldn't read." };
  }
  return {
    ok: true,
    track: {
      providerId: id,
      title: String(body.title || "").trim().slice(0, 300) || "Untitled",
      artist: body.author_name ? String(body.author_name).slice(0, 200) : null,
      permalink: url,
      artwork: isYouTubeThumb(body.thumbnail_url) ? body.thumbnail_url : null,
    },
  };
}
