// Tests the /api/radio routes end to end against the local stack:
//   preview "radio-fake-supabase" (port 54399) + "radio-site" (port 3100)
//   node scripts/radio-dev/api-test.mjs [--base=http://127.0.0.1:3100]
// Uses one real call to SoundCloud's public oEmbed endpoint (link check).
import assert from "node:assert/strict";

const arg = (n, d) => (process.argv.find((a) => a.startsWith(`--${n}=`)) || "").split("=")[1] || d;
const BASE = arg("base", "http://127.0.0.1:3100");
const DB = arg("db", "http://127.0.0.1:54399");
const S = "test-tavern";
let passed = 0;
const failures = [];
async function t(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`PASS ${name}`);
  } catch (e) {
    failures.push(name);
    console.log(`FAIL ${name}: ${e.message}`);
  }
}
async function api(method, path, { as, body, token } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (as) headers.Authorization = `Bearer dev-jwt-${as}`;
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(BASE + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const json = await res.json().catch(() => null);
  return { status: res.status, body: json, cache: res.headers.get("cache-control") };
}
const post = (action, as, body) => api("POST", `/api/radio/stations/${S}/${action}`, { as, body });
const state = (as) => api("GET", `/api/radio/stations/${S}`, { as }).then((r) => r.body);
const sql = (q, params) =>
  fetch(DB + "/dev/sql", { method: "POST", body: JSON.stringify({ sql: q, params }) }).then((r) => r.json());

// The early tests check the playlist's order, so they run with shuffle off.
await sql("update public.radio_stations set shuffle = false");

await t("station list and state need no sign-in, are never cached", async () => {
  const r = await api("GET", "/api/radio/stations");
  assert.equal(r.status, 200);
  assert.ok(r.body.stations.some((s) => s.slug === S));
  const st = await api("GET", `/api/radio/stations/${S}`);
  assert.equal(st.status, 200);
  assert.equal(st.cache, "no-store");
  assert.ok(Math.abs(st.body.serverNow - Date.now()) < 5000);
});
await t("unknown or malformed station is 404", async () => {
  assert.equal((await api("GET", "/api/radio/stations/nope")).status, 404);
  assert.equal((await api("GET", "/api/radio/stations/Bad%20Slug")).status, 404);
});
await t("actions need sign-in; bad tokens are refused", async () => {
  assert.equal((await post("presence", null, { listening: true })).status, 401);
  assert.equal((await api("POST", `/api/radio/stations/${S}/presence`, { token: "rdt_" + "0".repeat(64), body: { listening: true } })).status, 401);
  assert.equal((await api("POST", `/api/radio/stations/${S}/presence`, { token: "garbage", body: { listening: true } })).status, 401);
});
await t("bad input is a 400, not a crash", async () => {
  assert.equal((await post("skip", "bob", { instanceId: "not-a-uuid", vote: true })).status, 400);
  assert.equal((await post("vote", "bob", { queueId: "1; drop table", vote: true })).status, 400);
  assert.equal((await post("moderate", "alice", { action: "drop_everything" })).status, 400);
  const r = await fetch(`${BASE}/api/radio/stations/${S}/presence`, { method: "POST", headers: { Authorization: "Bearer dev-jwt-bob" }, body: "{oops" });
  assert.equal(r.status, 400);
});
await t("only the host can import the playlist", async () => {
  const tracks = [{ id: "1001", title: "A", durationMs: 60000 }];
  assert.equal((await post("import", "bob", { tracks })).status, 403);
});
await t("host imports; bad entries are dropped; station starts playing", async () => {
  const r = await post("import", "alice", {
    replace: true,
    tracks: [
      { id: "1001", title: "Song A", artist: "X", durationMs: 60000, permalink: "https://soundcloud.com/x/a", artwork: "https://i1.sndcdn.com/a.jpg" },
      { id: "1002", title: "Song B", artist: "X", durationMs: 61000, permalink: "javascript:alert(1)", artwork: "https://evil.example/a.jpg" },
      { id: "not-a-number", title: "Bad" },
      { id: "1001", title: "Duplicate" },
      { id: "1003", title: "Song C", durationMs: 62000 },
    ],
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.imported, 3);
  const cat = await api("GET", `/api/radio/stations/${S}/catalog`);
  assert.deepEqual(cat.body.tracks.map((x) => x.title), ["Song A", "Song B", "Song C"]);
  assert.equal(cat.body.tracks[1].permalinkUrl, null);
  assert.equal(cat.body.tracks[1].artworkUrl, null);
  const s = await state();
  assert.equal(s.now.source, "playlist");
  assert.equal(s.now.track.providerId, "1001");
});
await t("24/7: the station moves on with nobody tuned in", async () => {
  const a = await state();
  await sql("update public.radio_station_state set started_at = started_at - interval '61 seconds'");
  const b = await state();
  assert.notEqual(b.now.instanceId, a.now.instanceId);
  assert.equal(b.now.track.providerId, "1002");
});
await t("Spotify links become a labelled suggestion, never a queued song", async () => {
  const r = await post("request", "dan", { url: "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT" });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.suggestion.service, "Spotify");
  assert.match(r.body.suggestion.message, /shared stations/);
  const mine = r.body.queue.find((q) => q.mine);
  assert.equal(mine.status, "suggestion");
  assert.equal((await post("withdraw", "dan", { queueId: mine.id })).status, 200);
});
await t("playlists, profiles and junk are refused with a reason", async () => {
  for (const url of ["https://soundcloud.com/forss/sets/soulhack", "https://soundcloud.com/forss", "hello", "https://on.soundcloud.com/abc"]) {
    const r = await post("request", "dan", { url });
    assert.equal(r.status, 400, url);
    assert.ok(r.body.error.length > 10);
  }
});
await t("a real SoundCloud song link is checked and queued for approval", async () => {
  const r = await post("request", "cara", { url: "https://soundcloud.com/forss/flickermood" });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const mine = r.body.queue.find((q) => q.mine);
  assert.equal(mine.status, "needs_approval");
  assert.match(mine.track.providerId, /^\d+$/);
  assert.ok(/flickermood/i.test(mine.track.title), mine.track.title);
  const ok = await post("moderate", "alice", { action: "approve", args: { queueId: mine.id } });
  assert.equal(ok.status, 200);
});
await t("a YouTube link isn't played - it becomes a suggestion for the host", async () => {
  const r = await post("request", "dan", { url: "https://www.youtube.com/watch?v=M7lc1UVf-VE" });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.suggestion.service, "YouTube");
  assert.match(r.body.suggestion.message, /only SoundCloud/);
  const mine = r.body.queue.find((q) => q.mine);
  assert.equal(mine.status, "suggestion");
  assert.equal(mine.track, null);
  assert.equal((await post("withdraw", "dan", { queueId: mine.id })).status, 200);
});
await t("catalog request, votes and the 'one request' rule over HTTP", async () => {
  const cat = (await api("GET", `/api/radio/stations/${S}/catalog`)).body.tracks;
  const playing = (await state()).now.track.id;
  const pick = cat.find((x) => x.id !== playing);
  const r = await post("request", "bob", { trackId: pick.id });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const again = await post("request", "bob", { trackId: cat.find((x) => x.id !== playing && x.id !== pick.id).id });
  assert.equal(again.status, 409);
  assert.equal(again.body.code, "one_request");
  const q = r.body.queue.find((x) => x.mine);
  assert.equal((await post("vote", "dan", { queueId: q.id, vote: true })).body.queue.find((x) => x.id === q.id).votes, 1);
});
await t("vote to skip with tuned-in listeners", async () => {
  for (const u of ["bob", "cara", "dan"]) await post("presence", u, { listening: true });
  const s = await state("bob");
  assert.equal(s.listeners, 3);
  const r1 = await post("skip", "bob", { instanceId: s.now.instanceId, vote: true });
  assert.equal(r1.body.skip.votes, 1);
  const r2 = await post("skip", "cara", { instanceId: s.now.instanceId, vote: true });
  assert.notEqual(r2.body.now.instanceId, s.now.instanceId);
  const stale = await post("skip", "dan", { instanceId: s.now.instanceId, vote: true });
  assert.equal(stale.status, 409);
});
await t("a listener's problem report never skips the song", async () => {
  const s = await state("dan");
  assert.equal((await post("report", "dan", { instanceId: s.now.instanceId, kind: "unavailable", detail: "blocked here" })).status, 200);
  assert.equal((await state()).now.instanceId, s.now.instanceId);
});
await t("non-mods can't use moderator tools", async () => {
  const r = await post("moderate", "dan", { action: "advance" });
  assert.equal(r.status, 403);
});

let deviceToken;
await t("desktop sign-in: code from the website, redeemed once by the app", async () => {
  const c = await api("POST", "/api/radio/link/code", { as: "bob" });
  assert.equal(c.status, 200, JSON.stringify(c.body));
  assert.match(c.body.code, /^[A-Z0-9]{4}-[A-Z0-9]{4}$/);
  assert.match(c.body.appLink, /^wowforever:\/\/radio-link\?code=[A-Z0-9]{8}$/);
  const r = await api("POST", "/api/radio/link/redeem", { body: { code: c.body.code.toLowerCase(), label: "Bob's PC <script>" } });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.match(r.body.token, /^rdt_[0-9a-f]{64}$/);
  assert.equal(r.body.name, "Bob");
  deviceToken = r.body.token;
  const again = await api("POST", "/api/radio/link/redeem", { body: { code: c.body.code } });
  assert.equal(again.status, 400);
  const label = await sql("select label from public.radio_device_tokens order by created_at desc limit 1");
  assert.equal(label[0].label, "Bob's PC script");
});
await t("the radio token works for radio, can't mint codes, and can be revoked", async () => {
  const me = await api("GET", "/api/radio/me", { token: deviceToken });
  assert.equal(me.body.name, "Bob");
  assert.equal(me.body.via, "device");
  assert.equal((await api("POST", "/api/radio/link/code", { token: deviceToken })).status, 403);
  assert.equal((await api("POST", `/api/radio/stations/${S}/presence`, { token: deviceToken, body: { listening: true } })).status, 200);
  assert.equal((await api("POST", "/api/radio/link/revoke", { token: deviceToken })).status, 200);
  assert.equal((await api("GET", "/api/radio/me", { token: deviceToken })).status, 401);
});
await t("guessing codes is rate limited", async () => {
  let limited = false;
  for (let i = 0; i < 12 && !limited; i++) {
    const r = await api("POST", "/api/radio/link/redeem", { body: { code: "ZZZZ-ZZZZ" } });
    if (r.status === 429) limited = true;
  }
  assert.ok(limited);
});

// ---- The host's playlist: songs by link, playlists, shuffle ----
await t("only the host can add songs by link", async () => {
  const r = await post("add", "bob", { url: "https://soundcloud.com/forss/flickermood" });
  assert.equal(r.status, 403);
});
await t("host adds a real SoundCloud song by link (once - again is a duplicate)", async () => {
  const before = (await api("GET", `/api/radio/stations/${S}/catalog`)).body.tracks;
  const had = before.some((x) => x.providerId === "293");
  const a = await post("add", "alice", { url: "https://soundcloud.com/forss/flickermood" });
  if (had) assert.equal(a.status, 409, JSON.stringify(a.body));
  else assert.equal(a.status, 200, JSON.stringify(a.body));
  const again = await post("add", "alice", { url: "https://soundcloud.com/forss/flickermood" });
  assert.equal(again.status, 409);
  assert.match(again.body.error, /already/);
  const cat = (await api("GET", `/api/radio/stations/${S}/catalog`)).body.tracks;
  assert.equal(cat.length, before.length + (had ? 0 : 1));
  assert.ok(cat.some((x) => x.provider === "soundcloud" && x.providerId === "293" && /flickermood/i.test(x.title)));
});
await t("adding a playlist link or another service by link is refused with a reason", async () => {
  for (const url of ["https://soundcloud.com/forss/sets/soulhack", "https://www.youtube.com/watch?v=M7lc1UVf-VE", "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"]) {
    const r = await post("add", "alice", { url });
    assert.equal(r.status, 400, url);
    assert.ok(r.body.error.length > 10);
  }
});
await t("an import keeps only SoundCloud songs and counts the rest as skipped", async () => {
  const r = await post("import", "alice", {
    replace: false,
    tracks: [
      { provider: "youtube", id: "dQw4w9WgXcQ" },
      { provider: "soundcloud", id: "bad" },
      { provider: "soundcloud", id: "1104", title: "Song E", durationMs: 60000 },
    ],
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.imported, 1);
  assert.equal(r.body.skipped, 2);
  const cat = (await api("GET", `/api/radio/stations/${S}/catalog`)).body.tracks;
  assert.ok(!cat.some((x) => x.provider !== "soundcloud"));
  const yt = await post("import", "alice", { replace: false, tracks: [{ provider: "youtube", id: "dQw4w9WgXcQ" }] });
  assert.equal(yt.status, 400);
});
await t("the host switches shuffle on and off", async () => {
  assert.equal((await post("moderate", "bob", { action: "set_shuffle", args: { shuffle: true } })).status, 403);
  const on = await post("moderate", "alice", { action: "set_shuffle", args: { shuffle: true } });
  assert.equal(on.status, 200);
  assert.equal(on.body.station.shuffle, true);
  const off = await post("moderate", "alice", { action: "set_shuffle", args: { shuffle: false } });
  assert.equal(off.body.station.shuffle, false);
});

console.log(`\nradio API tests: ${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
