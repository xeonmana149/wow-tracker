import {
  addressKey, cleanLinkCode, DEVICE_TOKEN, fail, handle, newDeviceToken, newLinkCode, ok, readJson, requireCaller, rpc, sha256,
} from "../../../../../lib/radio/server";

// Azeroth Radio: signing the desktop app in, for the radio only.
//   POST /api/radio/link/code    website session -> a one-time code (10 min)
//   POST /api/radio/link/redeem  { code, label } -> a radio token for the app
//   POST /api/radio/link/revoke  the app's radio token -> signed out
// The token the app gets can do radio things and nothing else; it isn't the
// character-sync token and the website never sees it again after this.
export async function POST(req: Request, { params }: { params: Promise<{ step: string }> }) {
  return handle(async () => {
    const { step } = await params;
    if (step === "code") {
      const who = await requireCaller(req);
      if (who.via !== "website") fail("forbidden", "Get a code from the website while signed in.");
      const code = newLinkCode();
      await rpc("radio_create_link_code", { p_user: who.userId, p_code_hash: sha256(code.replace("-", "")) });
      return ok({ code, expiresInSeconds: 600, appLink: `wowforever://radio-link?code=${code.replace("-", "")}` });
    }
    if (step === "redeem") {
      const body = await readJson(req);
      await rpc("radio_rate", { p_user: addressKey(req), p_action: "redeem", p_max: 10, p_window: "10 minutes" });
      const code = cleanLinkCode(body.code);
      if (!code) fail("bad_code", "That code isn't right. Codes look like ABCD-EFGH.");
      const label = String(body.label ?? "Desktop app").replace(/[^\p{L}\p{N} ._()'-]/gu, "").trim().slice(0, 60) || "Desktop app";
      const token = newDeviceToken();
      const res = await rpc<{ name: string }>("radio_redeem_link_code", { p_code_hash: sha256(code), p_token_hash: sha256(token), p_label: label });
      return ok({ token, name: res.name });
    }
    if (step === "revoke") {
      const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim() ?? "";
      if (!DEVICE_TOKEN.test(bearer)) fail("not_signed_in", "Not signed in.");
      await rpc("radio_revoke_device", { p_token_hash: sha256(bearer) });
      return ok({ ok: true });
    }
    fail("not_found", "Unknown step.");
  });
}
