import { caller, fail, handle, ok, rpc, SLUG } from "../../../../../lib/radio/server";

// Azeroth Radio: one station's shared timeline. Reading it also moves the
// station on to whatever should be playing by now, so a station keeps
// "playing" with nobody connected and needs no timer. serverNow lets
// players line up their clocks with ours.
export async function GET(req: Request, { params }: { params: Promise<{ slug: string }> }) {
  return handle(async () => {
    const { slug } = await params;
    if (!SLUG.test(slug)) fail("not_found", "That station doesn't exist.");
    const who = await caller(req);
    return ok(await rpc("radio_get_state", { p_slug: slug, p_user: who?.userId ?? null }));
  });
}
