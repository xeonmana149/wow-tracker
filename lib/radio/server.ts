import crypto from "node:crypto";
import { NextResponse } from "next/server";
import { supabaseAdmin } from "../supabaseAdmin";

// Azeroth Radio: server-only helpers for the /api/radio routes. Every read
// and write goes through the radio_* SQL functions (sql/azeroth-radio.sql),
// which do the permission checks, rate limits and voting atomically. Those
// functions can only be run with the service role key, which stays here.

export class RadioError extends Error {
  constructor(public code: string, message: string, public status: number) {
    super(message);
  }
}

const STATUS: Record<string, number> = {
  bad_request: 400,
  bad_code: 400,
  unsupported: 400,
  not_signed_in: 401,
  forbidden: 403,
  not_found: 404,
  stale: 409,
  not_listening: 409,
  one_request: 409,
  duplicate: 409,
  playing: 409,
  curated_only: 409,
  paused: 409,
  rate_limited: 429,
};

export function fail(code: string, message: string): never {
  throw new RadioError(code, message, STATUS[code] ?? 400);
}

export async function rpc<T = unknown>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabaseAdmin.rpc(fn, args);
  if (error) {
    // radio_fail() puts a short code in the hint; anything else is unexpected.
    if (error.hint && STATUS[error.hint]) throw new RadioError(error.hint, error.message, STATUS[error.hint]);
    console.error(`radio ${fn} failed:`, error.message);
    throw new RadioError("server", "Something went wrong on our side. Try again in a moment.", 500);
  }
  return data as T;
}

export const sha256 = (s: string) => crypto.createHash("sha256").update(s).digest("hex");

// Desktop app sign-in tokens: "rdt_" + 64 hex. Only their hash is stored,
// and they're separate from the character-sync tokens.
export const DEVICE_TOKEN = /^rdt_[0-9a-f]{64}$/;
export const newDeviceToken = () => "rdt_" + crypto.randomBytes(32).toString("hex");

// Link codes: 8 characters, no look-alikes (0/O, 1/I/L), shown as XXXX-XXXX.
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export function newLinkCode() {
  const bytes = crypto.randomBytes(8);
  let s = "";
  for (const b of bytes) s += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return s.slice(0, 4) + "-" + s.slice(4);
}
export const cleanLinkCode = (raw: unknown) => {
  const s = String(raw ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  return s.length === 8 && [...s].every((c) => CODE_ALPHABET.includes(c)) ? s : null;
};

export type Caller = { userId: string; via: "device" | "website" };

// Who's calling: the desktop app's radio token, or the website's Supabase
// session. Returns null when signed out.
export async function caller(req: Request): Promise<Caller | null> {
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!bearer) return null;
  if (bearer.startsWith("rdt_")) {
    if (!DEVICE_TOKEN.test(bearer)) return null;
    const userId = await rpc<string | null>("radio_device_user", { p_token_hash: sha256(bearer) });
    return userId ? { userId, via: "device" } : null;
  }
  if (bearer.length > 4096) return null;
  const { data } = await supabaseAdmin.auth.getUser(bearer);
  return data?.user?.id ? { userId: data.user.id, via: "website" } : null;
}

export async function requireCaller(req: Request): Promise<Caller> {
  const c = await caller(req);
  if (!c) fail("not_signed_in", "Sign in to do that.");
  return c;
}

// A stable stand-in "user" for rate-limiting calls that have no account
// yet (redeeming a link code), keyed on the caller's address.
export function addressKey(req: Request) {
  const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || req.headers.get("x-real-ip") || "unknown";
  const h = sha256("radio-ip:" + ip);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
}

export const SLUG = /^[a-z0-9][a-z0-9-]{0,47}$/;

export async function readJson(req: Request): Promise<Record<string, unknown>> {
  const text = await req.text();
  if (text.length > 200_000) fail("bad_request", "That's too much at once.");
  if (!text) return {};
  try {
    const v = JSON.parse(text);
    if (v && typeof v === "object" && !Array.isArray(v)) return v;
  } catch {}
  fail("bad_request", "Couldn't read that request.");
}

const NO_STORE = { "Cache-Control": "no-store" };

export function ok(body: unknown) {
  return NextResponse.json(body, { headers: NO_STORE });
}

// Wraps a handler so errors come back as { error, code } with the right
// status, never as a stack trace.
export async function handle(fn: () => Promise<Response>): Promise<Response> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof RadioError) return NextResponse.json({ error: e.message, code: e.code }, { status: e.status, headers: NO_STORE });
    console.error("radio route failed:", e);
    return NextResponse.json({ error: "Something went wrong on our side.", code: "server" }, { status: 500, headers: NO_STORE });
  }
}
