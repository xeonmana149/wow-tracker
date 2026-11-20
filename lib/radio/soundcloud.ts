// Azeroth Radio: checking SoundCloud links on the server. Same rules as the
// desktop app's radio/soundcloud-url.js. Nothing here touches audio: the
// only network call is SoundCloud's public oEmbed endpoint, which says
// whether a track exists and may be embedded, plus its id, title, artist
// and artwork. Playback is always SoundCloud's own embedded player.

export type Normalized = { ok: true; url: string; kind: "playlist" | "track" } | { ok: false; error: string; other?: string };

const RESERVED_FIRST = new Set([
  "discover", "search", "stream", "you", "upload", "settings", "charts", "pages", "terms-of-use",
  "mobile", "jobs", "imprint", "notifications", "messages", "signin", "signup", "logout", "home",
  "feed", "people", "tags", "popular", "explore", "for-artists", "pro", "go", "artists", "premium",
]);
const NOT_A_TRACK = new Set([
  "tracks", "likes", "reposts", "followers", "following", "albums", "popular-tracks", "comments",
  "sets", "spotlight", "groups", "recommended",
]);
const SLUG = /^[A-Za-z0-9_-]{1,100}$/;
const SECRET = /^s-[A-Za-z0-9]{3,40}$/;

// Services stations can't play. A link to one of these becomes a labelled
// suggestion instead of a queued song. (YouTube links are handled before
// this, in youtube.ts.)
const OTHER_SERVICES: [RegExp, string][] = [
  [/(^|\.)spotify\.(com|link)$/, "Spotify"],
  [/(^|\.)bandcamp\.com$/, "Bandcamp"],
  [/(^|\.)music\.apple\.com$/, "Apple Music"],
  [/(^|\.)deezer\.com$/, "Deezer"],
  [/(^|\.)tidal\.com$/, "Tidal"],
];

const fail = (error: string, other?: string): Normalized => ({ ok: false, error, other });

export function normalizeSoundCloudUrl(input: unknown): Normalized {
  if (typeof input !== "string") return fail("Paste a SoundCloud link.");
  let text = input.trim();
  if (!text) return fail("Paste a SoundCloud link.");
  if (text.length > 2000) return fail("That's too long to be a SoundCloud link.");
  if (/w\.soundcloud\.com\/player/i.test(text)) {
    const m = /https:\/\/w\.soundcloud\.com\/player\/?\?[^"'\s<>]*/i.exec(text);
    let inner: string | null = null;
    try {
      inner = m ? new URL(m[0].replace(/&amp;/g, "&")).searchParams.get("url") : null;
    } catch {}
    if (!inner) return fail("That embed code doesn't contain a SoundCloud address.");
    text = inner.trim();
  }
  if (/^(?:www\.|m\.)?soundcloud\.com\//i.test(text)) text = "https://" + text;
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return fail("That isn't a web address. Copy the link from SoundCloud's Share button.");
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return fail("Only web links work here.");
  if (url.username || url.password || url.port) return fail("That link has extra parts SoundCloud links never have.");
  const host = url.hostname.toLowerCase();
  const parts = url.pathname.split("/").filter(Boolean);
  if (host === "on.soundcloud.com" || host === "snd.sc") {
    return fail("Short links can't be checked. Open it in your browser and copy the full soundcloud.com address.");
  }
  if (host === "api.soundcloud.com") {
    if (parts.length === 2 && (parts[0] === "playlists" || parts[0] === "tracks") && /^\d{1,20}$/.test(parts[1])) {
      return { ok: true, url: `https://api.soundcloud.com/${parts[0]}/${parts[1]}`, kind: parts[0] === "playlists" ? "playlist" : "track" };
    }
    return fail("That api.soundcloud.com link isn't a playlist or track.");
  }
  if (host !== "soundcloud.com" && host !== "www.soundcloud.com" && host !== "m.soundcloud.com") {
    for (const [re, name] of OTHER_SERVICES) {
      if (re.test(host)) {
        return fail(
          name === "Spotify"
            ? "Spotify doesn't allow its songs in shared stations - only SoundCloud and YouTube."
            : `${name} links can't be played in stations - only SoundCloud and YouTube.`,
          name
        );
      }
    }
    return fail("Only SoundCloud and YouTube links can be played.", "Other");
  }
  if (parts.length === 0) return fail("That's SoundCloud's home page - copy a song's link instead.");
  if (!parts.every((p) => SLUG.test(p))) return fail("That doesn't look like a SoundCloud link.");
  const [user, second, third] = parts.map((p) => p.toLowerCase());
  if (RESERVED_FIRST.has(user)) return fail("That's a SoundCloud page, not a song.");
  if (parts.length === 1) return fail("That's a profile. Open one of its songs and copy that link.");
  if (second === "sets") {
    if (!third) return fail("That's a list of playlists. Open one and copy its link.");
    if (parts.length > 4 || (parts.length === 4 && !SECRET.test(parts[3]))) return fail("That doesn't look like a SoundCloud playlist link.");
    return { ok: true, url: `https://soundcloud.com/${user}/sets/${third}${parts.length === 4 ? "/" + parts[3] : ""}`, kind: "playlist" };
  }
  if (NOT_A_TRACK.has(second)) return fail("That's part of a profile, not a song.");
  if (parts.length > 3 || (parts.length === 3 && !SECRET.test(parts[2]))) return fail("That doesn't look like a SoundCloud song link.");
  return { ok: true, url: `https://soundcloud.com/${user}/${second}${parts.length === 3 ? "/" + parts[2] : ""}`, kind: "track" };
}

export function isSoundCloudPage(raw: unknown): raw is string {
  try {
    const u = new URL(String(raw));
    return u.protocol === "https:" && !u.port && !u.username && /^(www\.|m\.)?soundcloud\.com$/i.test(u.hostname) && String(raw).length <= 500;
  } catch {
    return false;
  }
}

export function isArtworkUrl(raw: unknown): raw is string {
  try {
    const u = new URL(String(raw));
    return u.protocol === "https:" && !u.port && /(^|\.)sndcdn\.com$/i.test(u.hostname) && String(raw).length <= 500;
  } catch {
    return false;
  }
}

export type TrackInfo = { providerId: string; title: string; artist: string | null; permalink: string | null; artwork: string | null };

// Asks SoundCloud whether a track exists and can be embedded.
export async function lookUpTrack(url: string): Promise<{ ok: true; track: TrackInfo } | { ok: false; error: string }> {
  let res: Response;
  try {
    res = await fetch(`https://soundcloud.com/oembed?format=json&url=${encodeURIComponent(url)}`, {
      signal: AbortSignal.timeout(6000),
      headers: { Accept: "application/json" },
      cache: "no-store",
    });
  } catch {
    return { ok: false, error: "Couldn't reach SoundCloud to check that link. Try again in a moment." };
  }
  if (res.status === 404) return { ok: false, error: "SoundCloud can't find that song - it may be private or deleted." };
  if (res.status === 401 || res.status === 403) return { ok: false, error: "The artist doesn't allow that song to be played outside SoundCloud." };
  if (!res.ok) return { ok: false, error: "SoundCloud couldn't check that link right now." };
  let body: { html?: string; title?: string; author_name?: string; thumbnail_url?: string };
  try {
    body = await res.json();
  } catch {
    return { ok: false, error: "SoundCloud gave an answer we couldn't read." };
  }
  // The embed snippet names the song as api.soundcloud.com/tracks/<id>,
  // usually URL-encoded inside the player address.
  const html = String(body.html || "");
  if (/api\.soundcloud\.com(?:\/|%2F)playlists(?:\/|%2F)/i.test(html)) {
    return { ok: false, error: "That's a playlist - request one song at a time." };
  }
  const id = /api\.soundcloud\.com(?:\/|%2F)tracks(?:\/|%2F)(\d{1,20})/i.exec(html)?.[1];
  if (!id) return { ok: false, error: "SoundCloud didn't say which song that is." };
  const artist = body.author_name ? String(body.author_name).slice(0, 200) : null;
  let title = String(body.title || "").trim();
  if (artist && title.endsWith(` by ${artist}`)) title = title.slice(0, -(artist.length + 4));
  return {
    ok: true,
    track: {
      providerId: id,
      title: (title || "Untitled").slice(0, 300),
      artist,
      permalink: isSoundCloudPage(url) ? url : null,
      artwork: isArtworkUrl(body.thumbnail_url) ? body.thumbnail_url : null,
    },
  };
}
