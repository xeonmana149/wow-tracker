// Behaviour tests for sql/azeroth-radio.sql, run in-process (PGlite).
//   cd scripts/radio-dev && node sql-test.mjs
// "Time passing" is simulated by moving the station's started_at back.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import { startFakeSupabase, USERS } from "./fake-supabase.mjs";

const { rpc, db, close } = await startFakeSupabase({ port: 0, quiet: true });
const { alice, bob, cara, dan } = USERS;
const S = "test-tavern";
let passed = 0;
const failures = [];
async function t(name, fn) {
  try {
    await fn();
    passed++;
  } catch (e) {
    failures.push(name);
    console.log(`FAIL ${name}: ${e.message}`);
  }
}
async function call(fn, args) {
  const r = await rpc(fn, args);
  if (r.status !== 200) {
    const err = new Error(r.body.message);
    err.code = r.body.hint;
    throw err;
  }
  return r.body;
}
async function expectCode(code, p) {
  try {
    await p;
  } catch (e) {
    assert.equal(e.code, code, `expected ${code}, got ${e.code}: ${e.message}`);
    return;
  }
  assert.fail(`expected error ${code}`);
}
const state = (user = null) => call("radio_get_state", { p_slug: S, p_user: user });
const track = (id, dur, title) =>
  call("radio_upsert_track", {
    p_provider: "soundcloud",
    p_provider_id: String(id),
    p_title: title || `Track ${id}`,
    p_artist: "Artist",
    p_duration: dur,
    p_permalink: `https://soundcloud.com/a/t${id}`,
    p_artwork: null,
  });
const elapse = (ms) =>
  db.query("update public.radio_station_state set started_at = started_at - make_interval(secs => $1::float8 / 1000)", [ms]);
const sid = (await db.query("select id from public.radio_stations where slug = $1", [S])).rows[0].id;
// Most tests check the playlist's order, so they run with shuffle off; the
// shuffle tests at the end turn it on.
await db.query("update public.radio_stations set shuffle = false where slug = $1", [S]);

await t("empty station is idle", async () => {
  const s = await state();
  assert.equal(s.now.source, "idle");
  assert.equal(s.now.track, null);
});

await t("an empty station stays unchanged between reads", async () => {
  const a = await state();
  const b = await state();
  assert.equal(b.queueRev, a.queueRev);
  assert.equal(b.now.instanceId, a.now.instanceId);
});

const t1 = await track(101, 60000);
const t2 = await track(102, 60000);
const t3 = await track(103, 60000);

await t("only hosts/moderators manage the playlist", () =>
  expectCode("forbidden", call("radio_moderate", { p_slug: S, p_user: bob, p_action: "catalog_add", p_args: { trackIds: [t1] } })));

await t("host adds the curated playlist and it starts", async () => {
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "catalog_add", p_args: { trackIds: [t1, t2, t3] } });
  const s = await state();
  assert.equal(s.now.track.id, t1);
  assert.equal(s.now.source, "playlist");
  assert.equal(s.catalogSize, 3);
});

await t("timeline advances back to back while nobody listens", async () => {
  const a = await state();
  await elapse(61000);
  const b = await state();
  assert.equal(b.now.track.id, t2);
  assert.equal(b.now.startedAt, a.now.startedAt - 61000 + 60000, "next track starts exactly when the last ended");
  assert.notEqual(b.now.instanceId, a.now.instanceId);
  await elapse(125000); // two more tracks' worth: t3 then wrap to t1
  const c = await state();
  assert.equal(c.now.track.id, t1);
  assert.equal(c.now.startedAt, b.now.startedAt - 125000 + 120000);
});

await t("long-idle station restarts at now instead of replaying history", async () => {
  await elapse(10 * 3600 * 1000);
  const s = await state();
  assert.ok(Math.abs(s.serverNow - s.now.startedAt) < 2000);
});

const t9 = await track(109, 90000, "Outside the catalog");
let bobReq;
await t("request outside the catalog needs approval, seen only by requester + mods", async () => {
  const s = await call("radio_request", { p_slug: S, p_user: bob, p_track: t9, p_suggestion_url: null });
  bobReq = s.queue.find((q) => q.mine);
  assert.equal(bobReq.status, "needs_approval");
  assert.equal((await state(cara)).queue.length, 0);
  assert.equal((await state(alice)).queue.length, 1);
});
await t("one waiting request per account", () =>
  track(108, 60000).then((t8) => expectCode("one_request", call("radio_request", { p_slug: S, p_user: bob, p_track: t8, p_suggestion_url: null }))));
await t("no duplicate waiting tracks", () =>
  expectCode("duplicate", call("radio_request", { p_slug: S, p_user: cara, p_track: t9, p_suggestion_url: null })));
await t("non-mod can't approve", () =>
  expectCode("forbidden", call("radio_moderate", { p_slug: S, p_user: cara, p_action: "approve", p_args: { queueId: bobReq.id } })));
await t("can't vote for an unapproved request", () =>
  expectCode("not_found", call("radio_vote_queue", { p_slug: S, p_user: cara, p_queue: bobReq.id, p_vote: true })));
await t("host approves -> everyone sees it", async () => {
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "approve", p_args: { queueId: bobReq.id } });
  const s = await state(cara);
  assert.equal(s.queue.length, 1);
  assert.equal(s.queue[0].status, "pending");
  assert.equal(s.queue[0].requestedBy, "Bob");
});

let caraReq, caraTrack;
await t("catalog request goes straight in", async () => {
  const playing = (await state()).now.track.id;
  caraTrack = [t1, t2, t3].find((id) => id !== playing);
  const s = await call("radio_request", { p_slug: S, p_user: cara, p_track: caraTrack, p_suggestion_url: null });
  caraReq = s.queue.find((q) => q.mine);
  assert.equal(caraReq.status, "pending");
});
await t("the playing song can't be requested", async () => {
  const s = await state();
  await expectCode("playing", call("radio_request", { p_slug: S, p_user: dan, p_track: s.now.track.id, p_suggestion_url: null }));
});

await t("one upvote per account, withdrawable; most votes first, earliest breaks ties", async () => {
  // Tie at 0: bob's (earlier) first.
  let s = await state(dan);
  assert.deepEqual(s.queue.map((q) => q.id), [bobReq.id, caraReq.id]);
  await call("radio_vote_queue", { p_slug: S, p_user: dan, p_queue: caraReq.id, p_vote: true });
  await call("radio_vote_queue", { p_slug: S, p_user: dan, p_queue: caraReq.id, p_vote: true });
  s = await state(dan);
  assert.equal(s.queue[0].id, caraReq.id);
  assert.equal(s.queue[0].votes, 1);
  assert.equal(s.queue[0].myVote, true);
  await call("radio_vote_queue", { p_slug: S, p_user: dan, p_queue: caraReq.id, p_vote: false });
  s = await state(dan);
  assert.equal(s.queue[0].id, bobReq.id);
  await call("radio_vote_queue", { p_slug: S, p_user: dan, p_queue: caraReq.id, p_vote: true });
  await call("radio_vote_queue", { p_slug: S, p_user: alice, p_queue: caraReq.id, p_vote: true });
});

await t("queue changes never interrupt the current song", async () => {
  const a = await state();
  await call("radio_vote_queue", { p_slug: S, p_user: bob, p_queue: caraReq.id, p_vote: true });
  const b = await state();
  assert.equal(b.now.instanceId, a.now.instanceId);
});

await t("highest-voted request plays next, credited; then the next", async () => {
  const a = await state();
  await elapse((a.now.durationMs || 600000) + 1000);
  const b = await state();
  assert.equal(b.now.track.id, caraTrack);
  assert.equal(b.now.source, "request");
  assert.equal(b.now.requestedBy, "Cara");
  assert.ok(!b.queue.some((q) => q.id === caraReq.id));
  await elapse(61000);
  const c = await state();
  assert.equal(c.now.track.id, t9);
  assert.equal(c.now.requestedBy, "Bob");
  const played = await db.query("select status from public.radio_queue where id = $1", [caraReq.id]);
  assert.equal(played.rows[0].status, "played");
});

await t("unknown length plays as provisional until a listener reports it", async () => {
  const tNull = await track(120, null, "Length unknown");
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "catalog_clear", p_args: {} });
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "catalog_add", p_args: { trackIds: [tNull] } });
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "advance", p_args: {} });
  let s = await state();
  assert.equal(s.now.track.id, tNull);
  assert.equal(s.now.provisional, true);
  await call("radio_report_duration", { p_slug: S, p_user: bob, p_instance: s.now.instanceId, p_duration: 123456 });
  await call("radio_report_duration", { p_slug: S, p_user: cara, p_instance: s.now.instanceId, p_duration: 999999 });
  s = await state();
  assert.equal(s.now.durationMs, 123456);
  assert.equal(s.now.provisional, false);
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "catalog_add", p_args: { trackIds: [t1, t2, t3] } });
});

await t("skip counts active signed-in listeners; resets when the song changes", async () => {
  for (const u of [bob, cara, dan]) await call("radio_heartbeat", { p_slug: S, p_user: u, p_listening: true });
  let s = await state(bob);
  assert.equal(s.listeners, 3);
  assert.equal(s.skip.required, 2); // max(2, ceil(3 * 0.5))
  const inst = s.now.instanceId;
  s = await call("radio_vote_skip", { p_slug: S, p_user: bob, p_instance: inst, p_vote: true });
  assert.equal(s.skip.votes, 1);
  assert.equal(s.skip.mine, true);
  assert.equal(s.now.instanceId, inst);
  s = await call("radio_vote_skip", { p_slug: S, p_user: cara, p_instance: inst, p_vote: true });
  assert.notEqual(s.now.instanceId, inst, "2/2 skips the song");
  assert.equal(s.skip.votes, 0);
  await expectCode("stale", call("radio_vote_skip", { p_slug: S, p_user: dan, p_instance: inst, p_vote: true }));
});

await t("only listeners can vote to skip", async () => {
  const s = await state();
  await expectCode("not_listening", call("radio_vote_skip", { p_slug: S, p_user: alice, p_instance: s.now.instanceId, p_vote: true }));
});

await t("a voter who leaves stops counting; withdrawn votes drop", async () => {
  let s = await state();
  const inst = s.now.instanceId;
  await call("radio_vote_skip", { p_slug: S, p_user: bob, p_instance: inst, p_vote: true });
  await call("radio_heartbeat", { p_slug: S, p_user: bob, p_listening: false });
  s = await state();
  assert.equal(s.listeners, 2);
  assert.equal(s.skip.votes, 0);
  await call("radio_vote_skip", { p_slug: S, p_user: cara, p_instance: inst, p_vote: true });
  s = await call("radio_vote_skip", { p_slug: S, p_user: cara, p_instance: inst, p_vote: false });
  assert.equal(s.skip.votes, 0);
  assert.equal(s.now.instanceId, inst);
});

await t("stale presence stops counting after 45s", async () => {
  await db.query("update public.radio_presence set last_seen = now() - interval '50 seconds' where user_id = $1", [dan]);
  const s = await state();
  assert.equal(s.listeners, 1);
});

await t("threshold drop after departures skips on the next read", async () => {
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "set_skip", p_args: { minVotes: 1, ratio: 0.5 } });
  for (const u of [bob, cara, dan, alice]) await call("radio_heartbeat", { p_slug: S, p_user: u, p_listening: true });
  let s = await state();
  const inst = s.now.instanceId;
  s = await call("radio_vote_skip", { p_slug: S, p_user: bob, p_instance: inst, p_vote: true }); // 1 of 2
  assert.equal(s.now.instanceId, inst);
  for (const u of [cara, dan]) await call("radio_heartbeat", { p_slug: S, p_user: u, p_listening: false });
  s = await state(); // 2 listeners -> 1 required, bob's vote now wins
  assert.notEqual(s.now.instanceId, inst);
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "set_skip", p_args: { minVotes: 2, ratio: 0.5 } });
});

await t("the station keeps playing after every listener leaves", async () => {
  for (const u of [alice, bob, cara, dan]) await call("radio_heartbeat", { p_slug: S, p_user: u, p_listening: false });
  const a = await state();
  assert.equal(a.listeners, 0);
  await elapse(a.now.durationMs + 500);
  const b = await state();
  assert.notEqual(b.now.instanceId, a.now.instanceId);
  assert.ok(b.now.track);
});

await t("curated-only mode and paused requests refuse requests", async () => {
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "set_mode", p_args: { mode: "curated_only" } });
  await expectCode("curated_only", call("radio_request", { p_slug: S, p_user: dan, p_track: t2, p_suggestion_url: null }));
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "set_mode", p_args: { mode: "requests" } });
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "pause_requests", p_args: { paused: true } });
  await expectCode("paused", call("radio_request", { p_slug: S, p_user: dan, p_track: t2, p_suggestion_url: null }));
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "pause_requests", p_args: { paused: false } });
});

await t("in curated-only mode waiting requests don't play", async () => {
  const s0 = await call("radio_request", { p_slug: S, p_user: dan, p_track: t1, p_suggestion_url: null });
  const danReq = s0.queue.find((q) => q.mine);
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "set_mode", p_args: { mode: "curated_only" } });
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "advance", p_args: {} });
  const s = await state();
  assert.equal(s.now.source, "playlist");
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "set_mode", p_args: { mode: "requests" } });
  await call("radio_withdraw", { p_slug: S, p_user: dan, p_queue: danReq.id });
});

await t("unsupported links become labelled suggestions, never queued", async () => {
  const s = await call("radio_request", { p_slug: S, p_user: dan, p_track: null, p_suggestion_url: "https://youtu.be/x" });
  const sug = s.queue.find((q) => q.mine);
  assert.equal(sug.status, "suggestion");
  assert.equal((await state(cara)).queue.filter((q) => q.status === "suggestion").length, 0);
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "remove", p_args: { queueId: sug.id } });
});

await t("requests are rate limited", async () => {
  let hit = false;
  for (let i = 0; i < 8 && !hit; i++) {
    try {
      const s = await call("radio_request", { p_slug: S, p_user: cara, p_track: t2, p_suggestion_url: null });
      await call("radio_withdraw", { p_slug: S, p_user: cara, p_queue: s.queue.find((q) => q.mine).id });
    } catch (e) {
      if (e.code === "rate_limited") hit = true;
      else throw e;
    }
  }
  assert.ok(hit);
});

await t("simultaneous requests for the same song: exactly one wins", async () => {
  const t7 = await track(177, 60000);
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "catalog_add", p_args: { trackIds: [t7] } });
  const res = await Promise.allSettled(
    [alice, bob].map((u) => call("radio_request", { p_slug: S, p_user: u, p_track: t7, p_suggestion_url: null }))
  );
  assert.equal(res.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(res.find((r) => r.status === "rejected").reason.code, "duplicate");
});

await t("simultaneous votes from one account count once", async () => {
  const s = await state(dan);
  const q = s.queue[0];
  await Promise.all([1, 2, 3].map(() => call("radio_vote_queue", { p_slug: S, p_user: dan, p_queue: q.id, p_vote: true })));
  const after = await state(dan);
  assert.equal(after.queue.find((x) => x.id === q.id).votes, q.votes + 1);
});

await t("playlist import: mods only, keeps order, replace switches off the rest", async () => {
  const tracks = [
    { id: "9001", title: "One", artist: "A", durationMs: 30000, permalink: "https://soundcloud.com/a/one", artwork: null },
    { id: "9002", title: "Two", artist: "A", durationMs: 31000, permalink: "https://soundcloud.com/a/two", artwork: null },
  ];
  await expectCode("forbidden", call("radio_import_tracks", { p_slug: S, p_user: cara, p_tracks: tracks, p_replace: true }));
  const r = await call("radio_import_tracks", { p_slug: S, p_user: alice, p_tracks: tracks, p_replace: true });
  assert.equal(r.imported, 2);
  const cat = await call("radio_catalog", { p_slug: S, p_user: alice });
  assert.deepEqual(cat.map((x) => x.title), ["One", "Two"]);
  assert.equal(cat[1].durationMs, 31000);
  await call("radio_import_tracks", { p_slug: S, p_user: alice, p_tracks: [tracks[1], tracks[0]], p_replace: true });
  const again = await call("radio_catalog", { p_slug: S, p_user: alice });
  assert.deepEqual(again.map((x) => x.title), ["Two", "One"]);
});

await t("a song already in the playlist isn't added again", async () => {
  const tracks = [
    { id: "9301", title: "Dup A", artist: "A", durationMs: 30000, permalink: null, artwork: null },
    { id: "9302", title: "Dup B", artist: "A", durationMs: 30000, permalink: null, artwork: null },
  ];
  await call("radio_import_tracks", { p_slug: S, p_user: alice, p_tracks: tracks, p_replace: true });
  // Importing again (plus one new song, and one listed twice): only the new one is added.
  const more = [...tracks, { id: "9303", title: "Dup C", artist: "A", durationMs: 30000, permalink: null, artwork: null }, tracks[0]];
  const r = await call("radio_import_tracks", { p_slug: S, p_user: alice, p_tracks: more, p_replace: false });
  assert.equal(r.imported, 1);
  assert.equal(r.duplicates, 3);
  const cat = await call("radio_catalog", { p_slug: S, p_user: alice });
  assert.deepEqual(cat.map((x) => x.title), ["Dup A", "Dup B", "Dup C"]);
  // Adding one song that's already there is refused, and nothing moves.
  const tidA = cat[0].id;
  await expectCode("duplicate", call("radio_moderate", { p_slug: S, p_user: alice, p_action: "catalog_add", p_args: { trackIds: [tidA] } }));
  const cat2 = await call("radio_catalog", { p_slug: S, p_user: alice });
  assert.deepEqual(cat2.map((x) => x.title), ["Dup A", "Dup B", "Dup C"]);
  // A song that was removed can be added back (at the end).
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "catalog_remove", p_args: { trackId: tidA } });
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "catalog_add", p_args: { trackIds: [tidA] } });
  const cat3 = await call("radio_catalog", { p_slug: S, p_user: alice });
  assert.deepEqual(cat3.map((x) => x.title), ["Dup B", "Dup C", "Dup A"]);
  // Replace with a list that names a song twice keeps it once.
  const rep = await call("radio_import_tracks", { p_slug: S, p_user: alice, p_tracks: [tracks[1], tracks[1], tracks[0]], p_replace: true });
  assert.equal(rep.imported, 2);
  assert.equal(rep.duplicates, 1);
  const cat4 = await call("radio_catalog", { p_slug: S, p_user: alice });
  assert.deepEqual(cat4.map((x) => x.title), ["Dup B", "Dup A"]);
});

await t("only SoundCloud songs can be added (YouTube and Spotify are refused)", async () => {
  const yt = await rpc("radio_upsert_track", { p_provider: "youtube", p_provider_id: "M7lc1UVf-VE", p_title: "Demo", p_artist: "YT", p_duration: null, p_permalink: "https://www.youtube.com/watch?v=M7lc1UVf-VE", p_artwork: null });
  assert.equal(yt.status, 400);
  const bad = await rpc("radio_upsert_track", { p_provider: "soundcloud", p_provider_id: "abc", p_title: "x", p_artist: null, p_duration: null, p_permalink: null, p_artwork: null });
  assert.equal(bad.status, 400);
  const sp = await rpc("radio_upsert_track", { p_provider: "spotify", p_provider_id: "4cOdK2wGLETKBW3PvgPWqT", p_title: "x", p_artist: null, p_duration: null, p_permalink: null, p_artwork: null });
  assert.equal(sp.status, 400);
});

await t("old YouTube songs are taken out when the SQL is run again", async () => {
  await call("radio_import_tracks", {
    p_slug: S,
    p_user: alice,
    p_tracks: [{ provider: "soundcloud", id: "9101", title: "SC song", artist: "A", durationMs: 30000, permalink: null, artwork: null }],
    p_replace: true,
  });
  // A YouTube song from before (put in directly, as the old version could).
  const yt = (await db.query("insert into public.radio_tracks (provider, provider_id, title) values ('youtube', 'dQw4w9WgXcQ', 'Old YT') returning id")).rows[0].id;
  await db.query("insert into public.radio_station_tracks (station_id, track_id, position, active) values ($1, $2, 999, true)", [sid, yt]);
  assert.equal((await call("radio_catalog", { p_slug: S, p_user: alice })).length, 2);
  await db.exec(fs.readFileSync(new URL("../../sql/azeroth-radio.sql", import.meta.url), "utf8"));
  const cat = await call("radio_catalog", { p_slug: S, p_user: alice });
  assert.deepEqual(cat.map((x) => x.provider), ["soundcloud"]);
});

await t("only hosts/moderators can switch shuffle", () =>
  expectCode("forbidden", call("radio_moderate", { p_slug: S, p_user: bob, p_action: "set_shuffle", p_args: { shuffle: true } })));

await t("shuffle: every song once per round, never the same song twice in a row", async () => {
  // A clean ten-song playlist, played by a station with requests out of the way.
  await db.query("update public.radio_queue set status = 'removed' where status in ('pending', 'needs_approval')");
  const ids = [];
  for (let i = 0; i < 10; i++) ids.push(String(9200 + i));
  await call("radio_import_tracks", {
    p_slug: S,
    p_user: alice,
    p_tracks: ids.map((id) => ({ provider: "soundcloud", id, title: "S" + id, artist: "A", durationMs: 20000, permalink: null, artwork: null })),
    p_replace: true,
  });
  const s0 = await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "set_shuffle", p_args: { shuffle: true } });
  assert.equal(s0.station.shuffle, true);
  const played = [];
  let last = null;
  for (let i = 0; i < 30; i++) {
    await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "advance", p_args: {} });
    const s = await state();
    const title = s.now.track.title;
    assert.notEqual(title, last, "same song twice in a row");
    last = title;
    played.push(title);
  }
  // Rounds line up with the playlist after the first advance landed somewhere in round one,
  // so check every window of 10 in a row that starts at a round boundary: find one by
  // looking for 10 distinct songs in a row anywhere.
  let fullRound = false;
  for (let i = 0; i + 10 <= played.length; i++) if (new Set(played.slice(i, i + 10)).size === 10) fullRound = true;
  assert.ok(fullRound, "a full round of 10 different songs");
  const orders = [];
  for (let r = 0; r < 3; r++) orders.push(played.slice(r * 10, r * 10 + 10).join(","));
  assert.ok(new Set(orders).size > 1, "order changes between rounds");
  const counts = {};
  for (const p of played) counts[p] = (counts[p] || 0) + 1;
  assert.ok(Object.values(counts).every((c) => c >= 2 && c <= 4), "each song plays about as often: " + JSON.stringify(counts));
});

await t("songs added while shuffled mix into what's still to come", async () => {
  const r = await call("radio_import_tracks", {
    p_slug: S,
    p_user: alice,
    p_tracks: [{ provider: "soundcloud", id: "9777", title: "New one", artist: "SC", durationMs: 40000, permalink: null, artwork: null }],
    p_replace: false,
  });
  assert.equal(r.imported, 1);
  const s = await state();
  const cp = (await db.query("select curated_position from public.radio_station_state where station_id = $1", [sid])).rows[0].curated_position;
  const pos = (await db.query(
    "select t.position from public.radio_station_tracks t join public.radio_tracks k on k.id = t.track_id where t.station_id = $1 and k.provider_id = '9777'",
    [sid]
  )).rows[0].position;
  assert.ok(pos > cp, "the new song is still to come this round");
  const dupes = await db.query("select position, count(*) from public.radio_station_tracks where station_id = $1 and active group by position having count(*) > 1", [sid]);
  assert.equal(dupes.rows.length, 0, "no two songs share a place");
  assert.equal(s.catalogSize, 11);
});

await t("shuffle off plays in the order added", async () => {
  await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "set_shuffle", p_args: { shuffle: false } });
  const tracks = ["9301", "9302", "9303"].map((id) => ({ provider: "soundcloud", id, title: "O" + id, artist: "A", durationMs: 20000, permalink: null, artwork: null }));
  await call("radio_import_tracks", { p_slug: S, p_user: alice, p_tracks: tracks, p_replace: true });
  await db.query("update public.radio_station_state set curated_position = -1 where station_id = $1", [sid]);
  const seen = [];
  for (let i = 0; i < 4; i++) {
    await call("radio_moderate", { p_slug: S, p_user: alice, p_action: "advance", p_args: {} });
    seen.push((await state()).now.track.title);
  }
  assert.deepEqual(seen, ["O9301", "O9302", "O9303", "O9301"]);
});

const sha = (s) => crypto.createHash("sha256").update(s).digest("hex");
await t("desktop link codes are single-use and tokens revocable", async () => {
  await call("radio_create_link_code", { p_user: bob, p_code_hash: sha("CODE-1") });
  const r = await call("radio_redeem_link_code", { p_code_hash: sha("CODE-1"), p_token_hash: sha("tok-1"), p_label: "Test PC" });
  assert.equal(r.name, "Bob");
  await expectCode("bad_code", call("radio_redeem_link_code", { p_code_hash: sha("CODE-1"), p_token_hash: sha("tok-2"), p_label: "x" }));
  assert.equal(await call("radio_device_user", { p_token_hash: sha("tok-1") }), bob);
  await call("radio_revoke_device", { p_token_hash: sha("tok-1") });
  assert.equal(await call("radio_device_user", { p_token_hash: sha("tok-1") }), null);
});
await t("expired link codes don't work", async () => {
  await call("radio_create_link_code", { p_user: cara, p_code_hash: sha("CODE-2") });
  await db.query("update public.radio_link_codes set expires_at = now() - interval '1 second' where code_hash = $1", [sha("CODE-2")]);
  await expectCode("bad_code", call("radio_redeem_link_code", { p_code_hash: sha("CODE-2"), p_token_hash: sha("tok-3"), p_label: "x" }));
});

await t("rows hold no audio, only ids/titles/links", async () => {
  const cols = await db.query(
    "select table_name, column_name, data_type from information_schema.columns where table_name like 'radio_%' and data_type in ('bytea')"
  );
  assert.equal(cols.rows.length, 0);
});

console.log(`\nradio SQL tests: ${passed} passed, ${failures.length} failed${failures.length ? " (" + failures.join("; ") + ")" : ""}`);
await close();
process.exit(failures.length ? 1 : 0);
