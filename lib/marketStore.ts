// Server-only. The private Supabase Storage bucket the auction house
// features keep their files in (only this server, with the service role
// key, can read or write it).

import { gunzipSync, gzipSync } from "node:zlib";
import { supabaseAdmin } from "./supabaseAdmin";

const BUCKET = "market";
// Local development can keep its own copies of the per-house and per-user
// files (MARKET_STORE_PREFIX=dev/ in .env.development.local) so testing never
// touches the live data. Item names are shared public data either way.
const PREFIX = process.env.MARKET_STORE_PREFIX ?? "";
const key = (name: string) => (name.startsWith("item-info") ? name : PREFIX + name);

// Every file here is read, changed and written back, so a read must see the
// latest write. Storage downloads go through a CDN that can hand back the
// previous copy for a while after an overwrite; a fresh nonce per read skips
// it (and uploads ask not to be cached at all).
let nonce = 0;
export async function getFile(name: string): Promise<Buffer | null> {
  const { data, error } = await supabaseAdmin.storage
    .from(BUCKET)
    .download(key(name), { cacheNonce: `${Date.now()}-${++nonce}` }, { cache: "no-store" });
  if (error || !data) return null;
  return Buffer.from(await data.arrayBuffer());
}

let bucketChecked = false;
export async function putFile(name: string, body: Buffer, contentType: string): Promise<void> {
  const up = () => supabaseAdmin.storage.from(BUCKET).upload(key(name), body, { contentType, upsert: true, cacheControl: "0" });
  let { error } = await up();
  if (error && !bucketChecked) {
    // First run ever: the bucket doesn't exist yet.
    bucketChecked = true;
    await supabaseAdmin.storage.createBucket(BUCKET, { public: false });
    ({ error } = await up());
  }
  if (error) throw new Error(`storage upload ${name}: ${error.message}`);
}

export async function getJson<T>(name: string): Promise<T | null> {
  const buf = await getFile(name);
  if (!buf) return null;
  try {
    return JSON.parse(buf.toString("utf8")) as T;
  } catch {
    return null;
  }
}

export const putJson = (name: string, value: unknown) =>
  putFile(name, Buffer.from(JSON.stringify(value)), "application/json");

export async function getGzJson<T>(name: string): Promise<T | null> {
  const buf = await getFile(name);
  if (!buf) return null;
  try {
    return JSON.parse(gunzipSync(buf).toString("utf8")) as T;
  } catch {
    return null;
  }
}

export const putGzJson = (name: string, value: unknown) =>
  putFile(name, gzipSync(Buffer.from(JSON.stringify(value))), "application/gzip");
