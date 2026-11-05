// One-command release for the tray app + addon + website.
//
//   npm run release                      tray-only or addon-unchanged release
//   npm run release -- --addon 1.9.2     also bump the addon to 1.9.2
//   npm run release -- --dry-run         show what would happen, change nothing
//   npm run release -- --include app/Foo.tsx   also commit these site files
//
// What it does, in order:
//   1. Works out the addon version (toc + the Lua's meta.addonVersion, which
//      must agree) and the tray version. Every release needs a NEW tray
//      version - electron-updater only updates when the version goes up, and
//      the addon zip is served from the newest release - so if a GitHub
//      release for the tray's current version already exists, the patch
//      number is bumped automatically.
//   2. Builds the tray installer and publishes it to a GitHub release on
//      xeonmana149/wow-tracker, with WoWForeverTrackerAddon.zip attached
//      (the tray's zip-addon-for-publish.js hook does the zip). Needs GH_TOKEN.
//   3. Checks the release really has all four files friends' apps need.
//   4. Bumps LATEST_VERSIONS in lib/versions.ts, commits it (plus the addon
//      folder and any --include paths) and pushes main. Vercel deploys the
//      push, and from then on /api/versions tells every tray app about the
//      new addon, and the tray apps update themselves from the release.
//
// Only the paths listed above are committed - anything else uncommitted in
// the repo is left alone.

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO = "xeonmana149/wow-tracker";
const SITE_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const TRAY_DIR = "C:\\Users\\jorda\\OneDrive\\Desktop\\wow-tracker-tray";
const ADDON_DIR = path.join(SITE_DIR, "addon", "WoWForeverTracker");
const TOC = path.join(ADDON_DIR, "WoWForeverTracker.toc");
const LUA = path.join(ADDON_DIR, "WoWForeverTracker.lua");
const VERSIONS_TS = path.join(SITE_DIR, "lib", "versions.ts");
const TRAY_PKG = path.join(TRAY_DIR, "package.json");
const REQUIRED_ASSETS = [
  "latest.yml",
  "WoWForeverTrackerSetup.exe",
  "WoWForeverTrackerSetup.exe.blockmap",
  "WoWForeverTrackerAddon.zip",
];

// ---- args ----
const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const flag = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const newAddon = flag("--addon");
const includes = [];
args.forEach((a, i) => {
  if (a === "--include" && args[i + 1]) includes.push(args[i + 1]);
});

const log = (msg) => console.log(`[release] ${msg}`);
function fail(msg) {
  console.error(`[release] ERROR: ${msg}`);
  process.exit(1);
}
const isVersion = (v) => /^\d+\.\d+\.\d+$/.test(v);

function run(cmd, cmdArgs, cwd) {
  log(`$ ${cmd} ${cmdArgs.join(" ")}`);
  if (dryRun) return "";
  // Only npx needs a shell on Windows (it's npx.cmd). git must NOT go
  // through one, or cmd.exe splits the commit message on its spaces.
  const shell = process.platform === "win32" && cmd === "npx";
  return execFileSync(cmd, cmdArgs, { cwd, stdio: ["ignore", "pipe", "inherit"], shell })
    .toString()
    .trim();
}

async function gh(urlPath) {
  const headers = { Accept: "application/vnd.github+json", "User-Agent": "wow-tracker-release-script" };
  if (process.env.GH_TOKEN) headers.Authorization = `Bearer ${process.env.GH_TOKEN}`;
  const res = await fetch(`https://api.github.com/repos/${REPO}${urlPath}`, { headers });
  if (res.status === 404) return null;
  if (!res.ok) fail(`GitHub API ${urlPath} returned ${res.status}`);
  return res.json();
}

// ---- preflight ----
if (!process.env.GH_TOKEN && !dryRun) fail("GH_TOKEN isn't set - electron-builder needs it to publish the release.");
if (!fs.existsSync(TRAY_PKG)) fail(`Tray app source not found at ${TRAY_DIR}.`);
if (newAddon && !isVersion(newAddon)) fail(`--addon needs a version like 1.9.2, got "${newAddon}".`);

const branch = run("git", ["rev-parse", "--abbrev-ref", "HEAD"], SITE_DIR);
if (!dryRun && branch !== "main") fail(`Site repo is on "${branch}" - releases go out from main.`);

// ---- 1. versions ----
let toc = fs.readFileSync(TOC, "utf8");
let lua = fs.readFileSync(LUA, "utf8");
const tocVersion = toc.match(/^## Version:\s*(\S+)/m)?.[1];
const luaVersion = lua.match(/addonVersion = "([^"]+)"/)?.[1];
if (!tocVersion || !luaVersion) fail("Couldn't find the addon version in the .toc or .lua.");
if (!newAddon && tocVersion !== luaVersion) {
  fail(`Addon versions disagree: .toc says ${tocVersion}, .lua says ${luaVersion}. Pass --addon to set both.`);
}
const addonVersion = newAddon ?? tocVersion;
if (newAddon) {
  toc = toc.replace(/^## Version:\s*\S+/m, `## Version: ${addonVersion}`);
  lua = lua.replace(/addonVersion = "[^"]+"/, `addonVersion = "${addonVersion}"`);
  log(`Addon: ${tocVersion} -> ${addonVersion}`);
  if (!dryRun) {
    fs.writeFileSync(TOC, toc);
    fs.writeFileSync(LUA, lua);
  }
} else {
  log(`Addon: ${addonVersion} (unchanged)`);
}

const trayPkgText = fs.readFileSync(TRAY_PKG, "utf8");
const trayPkg = JSON.parse(trayPkgText);
let trayVersion = trayPkg.version;
if (await gh(`/releases/tags/v${trayVersion}`)) {
  const [maj, min, patch] = trayVersion.split(".").map(Number);
  const bumped = `${maj}.${min}.${patch + 1}`;
  log(`Tray: v${trayVersion} is already released - bumping to ${bumped}`);
  trayVersion = bumped;
  if (!dryRun) {
    fs.writeFileSync(TRAY_PKG, trayPkgText.replace(/"version":\s*"[^"]+"/, `"version": "${trayVersion}"`));
  }
} else {
  log(`Tray: ${trayVersion}`);
}

// ---- 2. build + publish ----
run("npx", ["electron-builder", "--win", "--publish", "always"], TRAY_DIR);

// ---- 3. check the release ----
if (!dryRun) {
  const release = await gh(`/releases/tags/v${trayVersion}`);
  if (!release) fail(`Release v${trayVersion} wasn't found on GitHub after publishing.`);
  if (release.draft) fail(`Release v${trayVersion} is still a draft - publish it on GitHub, then rerun.`);
  const names = release.assets.map((a) => a.name);
  const missing = REQUIRED_ASSETS.filter((n) => !names.includes(n));
  if (missing.length) fail(`Release v${trayVersion} is missing: ${missing.join(", ")}`);
  log(`Release v${trayVersion} is live with all ${REQUIRED_ASSETS.length} files.`);
}

// ---- 4. site versions + push ----
const versionsText = fs.readFileSync(VERSIONS_TS, "utf8");
const updated = versionsText
  .replace(/(addon:\s*")[^"]+(")/, `$1${addonVersion}$2`)
  .replace(/(tray:\s*")[^"]+(")/, `$1${trayVersion}$2`);
if (!dryRun) fs.writeFileSync(VERSIONS_TS, updated);
log(`lib/versions.ts -> addon ${addonVersion}, tray ${trayVersion}`);

const toCommit = ["lib/versions.ts", "addon/WoWForeverTracker", ...includes];
run("git", ["add", "--", ...toCommit], SITE_DIR);
const message = [
  `Release tray ${trayVersion}, addon ${addonVersion}`,
  "",
  "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>",
].join("\n");
run("git", ["commit", "-m", message, "--", ...toCommit], SITE_DIR);
run("git", ["push", "origin", "main"], SITE_DIR);

log(
  dryRun
    ? "Dry run finished - nothing was changed."
    : `Done. Vercel is deploying; once it's live, ${"https://wow-tracker-amber.vercel.app/api/versions"} should show addon ${addonVersion} / tray ${trayVersion}.`
);
