// Server-only helper for Blizzard's Game Data API (item search, item
// details, item sets). Never import this from a "use client" component -
// it reads BLIZZARD_CLIENT_ID/BLIZZARD_CLIENT_SECRET, which must only ever
// live in Vercel's Environment Variables (Project Settings > Environment
// Variables), never committed to the repo or sent to the browser.

type TokenCache = { token: string; expiresAt: number };
let cached: TokenCache | null = null;

// Client-credentials OAuth flow - this is app-to-app access (no player
// login involved), good for public game data like items and item sets.
// Blizzard's tokens last about 24h; cached in memory and only re-fetched
// once it's actually close to expiring, so most requests don't pay for a
// token round-trip at all.
async function getAccessToken(): Promise<string> {
  if (cached && cached.expiresAt > Date.now() + 60_000) {
    return cached.token;
  }

  const clientId = process.env.BLIZZARD_CLIENT_ID;
  const clientSecret = process.env.BLIZZARD_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    throw new Error("BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET are not set");
  }

  const basic = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
  const res = await fetch("https://oauth.battle.net/token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
    cache: "no-store",
  });

  if (!res.ok) {
    throw new Error(`Blizzard token request failed: ${res.status} ${await res.text()}`);
  }

  const data = (await res.json()) as { access_token: string; expires_in: number };
  cached = { token: data.access_token, expiresAt: Date.now() + data.expires_in * 1000 };
  return cached.token;
}

// Low-level GET against the regional Game Data API. `namespace` is
// Blizzard's term for which game/dataset a request pulls from (e.g.
// "static-us" for retail) - we don't yet know the right one for WoW
// Forever, so every caller passes it explicitly rather than this baking in
// a guess.
export async function blizzardGet(
  region: string,
  path: string,
  params: Record<string, string>
): Promise<{ ok: boolean; status: number; body: unknown }> {
  const token = await getAccessToken();
  const url = new URL(`https://${region}.api.blizzard.com${path}`);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }

  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store",
  });

  let body: unknown;
  try {
    body = await res.json();
  } catch {
    body = await res.text().catch(() => null);
  }

  return { ok: res.ok, status: res.status, body };
}