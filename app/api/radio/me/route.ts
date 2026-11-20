import { handle, ok, requireCaller, rpc } from "../../../../lib/radio/server";

// Azeroth Radio: who the radio thinks you are, and the stations you host or
// moderate.
export async function GET(req: Request) {
  return handle(async () => {
    const who = await requireCaller(req);
    return ok({ ...(await rpc<Record<string, unknown>>("radio_me", { p_user: who.userId })), via: who.via });
  });
}
