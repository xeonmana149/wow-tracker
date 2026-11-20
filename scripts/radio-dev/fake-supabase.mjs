// Local stand-in for Supabase, for testing Azeroth Radio without touching the
// real database. Runs Postgres in-process (PGlite), loads sql/azeroth-radio.sql
// and answers the two Supabase endpoints the /api/radio routes use:
//   POST /rest/v1/rpc/<radio_function>   (supabase-js .rpc())
//   GET  /auth/v1/user                    (supabase-js auth.getUser(jwt))
//
//   cd scripts/radio-dev && npm install && node fake-supabase.mjs [--port=54399]
//
// Then run the site against it:
//   NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54399 SUPABASE_SERVICE_ROLE_KEY=dev
//   NEXT_PUBLIC_SUPABASE_ANON_KEY=dev npx next dev -p 3100
//
// Test accounts: a website session token "dev-jwt-<name>" signs in as that
// user (alice is the host of the "test-tavern" station). Only radio_*
// functions are reachable. Nothing is saved unless --data=DIR is given.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const here = path.dirname(fileURLToPath(import.meta.url));
const arg = (name, dflt) => (process.argv.find((a) => a.startsWith(`--${name}=`)) || "").split("=")[1] || dflt;
const PORT = Number(arg("port", "54399"));
const DATA = arg("data", "");

export const USERS = {
  alice: "00000000-0000-4000-8000-00000000a11c",
  bob: "00000000-0000-4000-8000-000000000b0b",
  cara: "00000000-0000-4000-8000-0000000000ca",
  dan: "00000000-0000-4000-8000-0000000000da",
};

export async function startFakeSupabase({ port = PORT, data = DATA, quiet = false } = {}) {
  const db = data ? new PGlite(data) : new PGlite();
  await db.exec(`
    create table if not exists public.profiles (id uuid primary key, display_name text);
  `);
  for (const [name, id] of Object.entries(USERS)) {
    await db.query("insert into public.profiles (id, display_name) values ($1, $2) on conflict do nothing", [
      id,
      name[0].toUpperCase() + name.slice(1),
    ]);
  }
  await db.exec(fs.readFileSync(path.join(here, "..", "..", "sql", "azeroth-radio.sql"), "utf8"));
  const exists = await db.query("select 1 from public.radio_stations where slug = 'test-tavern'");
  if (!exists.rows.length) {
    await db.query("select public.radio_create_station('test-tavern', 'Test Tavern', 'Local test station', $1)", [USERS.alice]);
  }

  // One call at a time, each in its own transaction - like separate requests
  // to a real database, minus true parallelism (row locks still apply).
  let chain = Promise.resolve();
  const serial = (fn) => {
    const p = chain.then(fn, fn);
    chain = p.catch(() => {});
    return p;
  };

  async function rpc(fn, args) {
    if (!/^radio_[a-z_]+$/.test(fn)) return { status: 404, body: { message: "Not found" } };
    const keys = Object.keys(args || {});
    if (!keys.every((k) => /^p_[a-z_]+$/.test(k))) return { status: 400, body: { message: "Bad argument name" } };
    const values = keys.map((k) => {
      const v = args[k];
      return v !== null && typeof v === "object" ? JSON.stringify(v) : v;
    });
    const sql = `select public.${fn}(${keys.map((k, i) => `${k} => $${i + 1}`).join(", ")}) as r`;
    return serial(async () => {
      try {
        const res = await db.transaction(async (tx) => tx.query(sql, values));
        return { status: 200, body: res.rows[0] ? res.rows[0].r : null };
      } catch (e) {
        return { status: 400, body: { code: e.code || "XX000", message: e.message, hint: e.hint || null, details: e.detail || null } };
      }
    });
  }

  const server = http.createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => (raw += c));
    req.on("end", async () => {
      const send = (status, body) => {
        res.writeHead(status, { "Content-Type": "application/json" });
        res.end(body === undefined ? "" : JSON.stringify(body));
      };
      const url = new URL(req.url, "http://x");
      const m = /^\/rest\/v1\/rpc\/([a-z_]+)$/.exec(url.pathname);
      if (m && req.method === "POST") {
        let args = {};
        try {
          args = raw ? JSON.parse(raw) : {};
        } catch {
          return send(400, { message: "Bad JSON" });
        }
        const r = await rpc(m[1], args);
        if (!quiet && r.status !== 200) console.log(`rpc ${m[1]} -> ${r.status} ${r.body.hint || ""} ${r.body.message}`);
        return send(r.status, r.body);
      }
      if (url.pathname === "/auth/v1/user" && req.method === "GET") {
        const jwt = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
        const who = /^dev-jwt-([a-z]+)$/.exec(jwt);
        if (!who || !USERS[who[1]]) return send(401, { msg: "invalid JWT", error_code: "bad_jwt" });
        return send(200, { id: USERS[who[1]], aud: "authenticated", role: "authenticated", email: `${who[1]}@example.test` });
      }
      // Test-only: run a query (localhost only, for test scripts).
      if (url.pathname === "/dev/sql" && req.method === "POST") {
        const { sql, params } = JSON.parse(raw || "{}");
        try {
          const r = await serial(() => db.query(sql, params || []));
          return send(200, r.rows);
        } catch (e) {
          return send(400, { message: e.message });
        }
      }
      send(404, { message: "Not found" });
    });
  });
  await new Promise((r) => server.listen(port, "127.0.0.1", r));
  if (!quiet) console.log(`fake Supabase on http://127.0.0.1:${port} (station: test-tavern, host: alice)`);
  return { db, server, rpc, close: () => new Promise((r) => server.close(() => db.close().then(r))) };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  startFakeSupabase().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
