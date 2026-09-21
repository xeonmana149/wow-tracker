import { NextResponse } from "next/server";
import { LATEST_VERSIONS, DOWNLOAD_URLS } from "../../../lib/versions";

// Public on purpose - just version numbers and download paths, nothing
// account-specific, so both the tray app and (once wired up) the addon can
// check this without any token. Also handy to hit directly in a browser
// to confirm what the live site currently thinks the latest versions are.
export async function GET() {
  return NextResponse.json({ latest: LATEST_VERSIONS, downloadUrls: DOWNLOAD_URLS });
}