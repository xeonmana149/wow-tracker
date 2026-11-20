import { fail, handle, ok, readJson, requireCaller, rpc, SLUG } from "../../../../../../lib/radio/server";
import { isArtworkUrl, isSoundCloudPage, lookUpTrack, normalizeSoundCloudUrl } from "../../../../../../lib/radio/soundcloud";
import { lookUpYouTube, parseYouTubeUrl } from "../../../../../../lib/radio/youtube";

// Azeroth Radio: things a signed-in listener (or a station's host and
// moderators) can do. The SQL functions enforce who may do what, the
// one-request / one-vote rules and the rate limits; this only checks the
// shape of what was sent and validates song links with SoundCloud or YouTube.
//
//   GET  catalog                                   the station's own playlist
//   POST presence  { listening }                   heartbeat / leave
//   POST skip      { instanceId, vote }            vote to skip the current song
//   POST request   { url } | { trackId }           ask for a song (SoundCloud or
//                                                  YouTube; other links become suggestions)
//   POST withdraw  { queueId }                     take your request back
//   POST vote      { queueId, vote }               upvote / withdraw upvote
//   POST duration  { instanceId, durationMs }      player-reported song length
//   POST report    { instanceId, kind, detail }    "it doesn't play for me"
//   POST moderate  { action, args }                host / moderator tools
//   POST import    { tracks, replace }             host / moderator: set the playlist

type Ctx = { params: Promise<{ slug: string; action: string }> };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const uuid = (v: unknown) => (typeof v === "string" && UUID.test(v) ? v : fail("bad_request", "Missing or bad instanceId."));
const id = (v: unknown, what: string) =>
  typeof v === "number" && Number.isSafeInteger(v) && v > 0 ? v : fail("bad_request", `Missing or bad ${what}.`);
const bool = (v: unknown, what: string) => (typeof v === "boolean" ? v : fail("bad_request", `Missing ${what}.`));
const REPORT_KINDS = new Set(["unavailable", "preview", "blocked", "network", "autoplay", "sync", "other"]);
const MOD_ACTIONS = new Set(["approve", "remove", "advance", "set_mode", "pause_requests", "set_skip", "catalog_remove", "catalog_clear"]);

async function slugOf(params: Ctx["params"]) {
  const { slug, action } = await params;
  if (!SLUG.test(slug)) fail("not_found", "That station doesn't exist.");
  return { slug, action };
}

export async function GET(req: Request, { params }: Ctx) {
  return handle(async () => {
    const { slug, action } = await slugOf(params);
    if (action !== "catalog") fail("not_found", "Unknown action.");
    return ok({ tracks: await rpc("radio_catalog", { p_slug: slug, p_user: null }) });
  });
}

export async function POST(req: Request, { params }: Ctx) {
  return handle(async () => {
    const { slug, action } = await slugOf(params);
    const who = await requireCaller(req);
    const b = await readJson(req);
    const u = who.userId;
    switch (action) {
      case "presence":
        return ok(await rpc("radio_heartbeat", { p_slug: slug, p_user: u, p_listening: bool(b.listening, "listening") }));
      case "skip":
        return ok(await rpc("radio_vote_skip", { p_slug: slug, p_user: u, p_instance: uuid(b.instanceId), p_vote: bool(b.vote, "vote") }));
      case "withdraw":
        return ok(await rpc("radio_withdraw", { p_slug: slug, p_user: u, p_queue: id(b.queueId, "queueId") }));
      case "vote":
        return ok(await rpc("radio_vote_queue", { p_slug: slug, p_user: u, p_queue: id(b.queueId, "queueId"), p_vote: bool(b.vote, "vote") }));
      case "duration": {
        const ms = id(b.durationMs, "durationMs");
        await rpc("radio_report_duration", { p_slug: slug, p_user: u, p_instance: uuid(b.instanceId), p_duration: Math.min(ms, 2147483647) });
        return ok({ ok: true });
      }
      case "report": {
        const kind = REPORT_KINDS.has(String(b.kind)) ? String(b.kind) : "other";
        const detail = String(b.detail ?? "").slice(0, 300);
        await rpc("radio_report_problem", { p_slug: slug, p_user: u, p_instance: uuid(b.instanceId), p_kind: kind, p_detail: detail });
        return ok({ ok: true });
      }
      case "request":
        return ok(await request(slug, u, b));
      case "moderate": {
        const act = String(b.action ?? "");
        if (!MOD_ACTIONS.has(act)) fail("bad_request", "Unknown moderator action.");
        const args = b.args && typeof b.args === "object" && !Array.isArray(b.args) ? b.args : {};
        return ok(await rpc("radio_moderate", { p_slug: slug, p_user: u, p_action: act, p_args: args }));
      }
      case "import":
        return ok(await importTracks(slug, u, b));
      default:
        fail("not_found", "Unknown action.");
    }
  });
}

async function request(slug: string, user: string, b: Record<string, unknown>) {
  if (b.trackId !== undefined) {
    return rpc("radio_request", { p_slug: slug, p_user: user, p_track: id(b.trackId, "trackId"), p_suggestion_url: null });
  }
  const raw = typeof b.url === "string" ? b.url.trim() : "";
  if (!raw) fail("bad_request", "Paste a SoundCloud or YouTube link to a song.");
  if (raw.length > 2000) fail("unsupported", "That's too long to be a song link.");

  const yt = parseYouTubeUrl(raw);
  if (yt) {
    if (!yt.ok) fail("unsupported", yt.error);
    await rpc("radio_rate", { p_user: user, p_action: "lookup", p_max: 15, p_window: "10 minutes" });
    const found = await lookUpYouTube(yt.id);
    if (!found.ok) fail("unsupported", found.error);
    const t = found.track;
    const trackId = await rpc<number>("radio_upsert_track", {
      p_provider: "youtube",
      p_provider_id: t.providerId,
      p_title: t.title,
      p_artist: t.artist,
      p_duration: null,
      p_permalink: t.permalink,
      p_artwork: t.artwork,
    });
    return rpc("radio_request", { p_slug: slug, p_user: user, p_track: trackId, p_suggestion_url: null });
  }

  const norm = normalizeSoundCloudUrl(raw);
  if (!norm.ok) {
    // A link to a service we can't play: keep it as a labelled suggestion
    // for the host to see, never as something to play.
    if (norm.other) {
      let link: URL | null = null;
      try {
        link = new URL(raw);
      } catch {}
      if (!link || link.protocol !== "https:" || raw.length > 500) fail("unsupported", norm.error);
      const state = await rpc("radio_request", { p_slug: slug, p_user: user, p_track: null, p_suggestion_url: link.toString() });
      return { ...(state as object), suggestion: { service: norm.other, message: `${norm.error} Saved as a suggestion for the host.` } };
    }
    fail("unsupported", norm.error);
  }
  if (norm.kind === "playlist") fail("unsupported", "That's a playlist - request one song at a time.");
  // Counts lookups too, so nobody can make us call SoundCloud endlessly.
  await rpc("radio_rate", { p_user: user, p_action: "lookup", p_max: 15, p_window: "10 minutes" });
  const found = await lookUpTrack(norm.url);
  if (!found.ok) fail("unsupported", found.error);
  const t = found.track;
  const trackId = await rpc<number>("radio_upsert_track", {
    p_provider: "soundcloud",
    p_provider_id: t.providerId,
    p_title: t.title,
    p_artist: t.artist,
    p_duration: null,
    p_permalink: t.permalink,
    p_artwork: t.artwork,
  });
  return rpc("radio_request", { p_slug: slug, p_user: user, p_track: trackId, p_suggestion_url: null });
}

// The host's desktop app reads the playlist through SoundCloud's own player
// and sends what it says about each song. Only ids, titles and links - never
// audio.
async function importTracks(slug: string, user: string, b: Record<string, unknown>) {
  if (!Array.isArray(b.tracks) || b.tracks.length === 0) fail("bad_request", "No songs to import.");
  if (b.tracks.length > 500) fail("bad_request", "Import up to 500 songs at a time.");
  const seen = new Set<string>();
  const tracks = [];
  for (const raw of b.tracks as Record<string, unknown>[]) {
    if (!raw || typeof raw !== "object") continue;
    const pid = String(raw.id ?? "");
    if (!/^\d{1,20}$/.test(pid) || seen.has(pid)) continue;
    seen.add(pid);
    const dur = Number(raw.durationMs);
    tracks.push({
      id: pid,
      title: String(raw.title ?? "").trim().slice(0, 300) || "Untitled",
      artist: raw.artist ? String(raw.artist).trim().slice(0, 200) : null,
      durationMs: Number.isFinite(dur) && dur >= 1000 && dur <= 10_800_000 ? Math.round(dur) : null,
      permalink: isSoundCloudPage(raw.permalink) ? raw.permalink : null,
      artwork: isArtworkUrl(raw.artwork) ? raw.artwork : null,
    });
  }
  if (!tracks.length) fail("bad_request", "None of those songs had a SoundCloud id.");
  return rpc("radio_import_tracks", { p_slug: slug, p_user: user, p_tracks: tracks, p_replace: b.replace === true });
}
