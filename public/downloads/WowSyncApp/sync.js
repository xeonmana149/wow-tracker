#!/usr/bin/env node
// WoW Forever Tracker - Background Sync (tray version, multi-character,
// account-level token)
//
// Runs quietly in the system tray. Watches every character on this PC
// you've ticked in Settings, and syncs each one to the website using a
// single account-wide sync token - the website creates a new character
// row automatically the first time it sees one it doesn't recognize yet.
// Switching characters in-game just means a different file gets updated -
// this app notices and syncs whichever one changed.
//
// You should not need to open or edit this file - everything is done
// through the tray icon menu and the setup page in your browser.

const fs = require("fs");
const path = require("path");
const os = require("os");
const http = require("http");
const https = require("https");
const { URL } = require("url");
const { exec } = require("child_process");

let SysTray, notifier;
try {
  const systrayModule = require("systray2");
  SysTray = systrayModule && systrayModule.default ? systrayModule.default : systrayModule;
} catch (e) {
  SysTray = null;
}
try {
  notifier = require("node-notifier");
} catch (e) {
  notifier = null;
}

const CONFIG_PATH = path.join(__dirname, "config.json");
const LOCK_PATH = path.join(__dirname, "sync.lock");
const SETUP_PORT = 47891;

// Pre-filled so friends don't have to type/paste this - it's the same
// site for everyone. They can still change it if it ever moves.
const DEFAULT_SITE_URL = "https://wow-tracker-amber.vercel.app";

// Bump this to match lib/versions.ts's "tray" value every time you package
// a new build of this app to send out. Sent along with every sync (see
// postSync below) so the website can tell you're on an old copy and show
// its own "update available" banner - this app no longer checks or nags
// about that itself.
const TRAY_VERSION = "1.0.0";

// ---------------------------------------------------------------------
// Only ever allow one copy of this app to run at once. Without this, if
// you double-click the launcher again (or it's both in Windows Startup
// AND started manually), you'd get two tray icons and two background
// loops both syncing and both popping notifications for the same events.
// ---------------------------------------------------------------------
function isProcessRunning(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return false;
  }
}

function acquireLock() {
  if (fs.existsSync(LOCK_PATH)) {
    const existingPid = parseInt(fs.readFileSync(LOCK_PATH, "utf8").trim(), 10);
    if (existingPid && isProcessRunning(existingPid)) {
      return false;
    }
  }
  fs.writeFileSync(LOCK_PATH, String(process.pid));
  return true;
}

function releaseLock() {
  try {
    if (fs.existsSync(LOCK_PATH)) {
      const existingPid = parseInt(fs.readFileSync(LOCK_PATH, "utf8").trim(), 10);
      if (existingPid === process.pid) fs.unlinkSync(LOCK_PATH);
    }
  } catch (e) {
    // Not worth failing over.
  }
}

const TRAY_ICON_BASE64 =
  "AAABAAEAICAAAAAAIADdAgAAFgAAAIlQTkcNChoKAAAADUlIRFIAAAAgAAAAIAgGAAAAc3p69AAAAqRJREFUeJzNlz1z00AQhl8L+UsG4kmACQmQDImcwbHrUEJLxw+gg4Ye6jT0dCn4BzR0/AMKGoYZrMSJnQQH4kkggdhG/pQlCkmnO1k6ScGesNWd97Tvo9313Qm4YItFfaD0bs3g+QuPP0aKGXpxkPB5QQIXuYUfPfvCXf/+TTESCNdJiwcJ80B4EL4OWzyqsB+IH4QwSXE6hl8PjQCMUzwMBAMwCfEgCNHvgQdrWbx8ehsAcHo2wJMXZca/sS5jYT4FAPjwqYlXGzXik9IC3r7OQxDMsj9fr+DrYddTh2TA/falHZUsmsnGcfN6gswvS5dwZy5F5gVZYoLeW8oQ8T/tIWp1U9wrC55NCAAnvwc4Ouk7IrkMGeeXJcSonp66IuLWbJLMi7KzdrPahsHZwgSayF17peJkoUAFtcf1Hz30BzoAYJXyr+acjJSoGLSGrembAYAtAyNgjT9vqdje71hQpmhcjCG36AAoLgC38QEqbTKeu5HA9JSIRFyAvJC2/CqBtKFW7kqIi2Z9+gMdlVqHC+D7LwCAw+MezpoasldFItJoaRAtAaWiotHUAACz1xKYycaZUpX3OtA0/hnGzQDA1rAgZ8ibHp/28fPXAFt7bQx1g/KHT384AKoPCrkMeUNlxyxPt6ejaqW5uJJBfsnJgLsBzwdABVmcTyG/LI38rli98vB+FumUGVLXDZR32wiyQID9712onSEAIBYDkgnBEnUA7Cylk0643YMuOj09HIB9VLovEwBgGOZmQlujpeHbUY/Mlao6stn4pd99PAdmAGD7wBRkgVrqEAd1dq/frAbXH3BdSCZ5GgLel5NQGZikMQC8XvhX87uajWRgEhC8e6FnCcYJEXQp/X+v5V4QYUDG+mHCAwmysX2aRQWJ+nF64fYX+HY+KHIvom0AAAAASUVORK5CYII=";

function notify(title, message) {
  if (notifier) {
    try {
      notifier.notify({ title, message, appID: "WoW Forever Tracker" });
      return;
    } catch (e) {
      // fall through to console
    }
  }
  console.log(title + ": " + message);
}

function openInBrowser(url) {
  const platform = process.platform;
  const cmd =
    platform === "win32"
      ? `start "" "${url}"`
      : platform === "darwin"
      ? `open "${url}"`
      : `xdg-open "${url}"`;
  exec(cmd, () => {});
}

// ---------------------------------------------------------------------
// Finding every character's SavedVariables file automatically
// ---------------------------------------------------------------------
// Finds likely WoW install folders without assuming which drive or path
// someone installed to - Battle.net lets people put it anywhere. On
// Windows this checks every drive letter that exists, looking up to two
// folders deep for anything with "warcraft" in the name (catches
// D:/World of Warcraft, D:/Games/World of Warcraft, E:/Blizzard/World of
// Warcraft, etc). This only runs when the Settings page is opened, not
// on every sync, so a couple of seconds of disk scanning is fine.
function findWowInstallRoots() {
  const roots = [];

  if (process.platform === "win32") {
    for (let i = 65; i <= 90; i++) {
      const drive = `${String.fromCharCode(i)}:/`;
      let topEntries;
      try {
        topEntries = fs.readdirSync(drive, { withFileTypes: true });
      } catch (e) {
        continue; // drive doesn't exist, or isn't ready (e.g. empty DVD drive)
      }

      const scanLevel = (dir, entries, depth) => {
        for (const entry of entries) {
          if (!entry.isDirectory()) continue;
          const full = path.join(dir, entry.name);
          if (/warcraft/i.test(entry.name)) {
            roots.push(full);
            continue; // no need to look inside a folder we already matched
          }
          if (depth < 2) {
            let subEntries;
            try {
              subEntries = fs.readdirSync(full, { withFileTypes: true });
            } catch (e) {
              continue;
            }
            scanLevel(full, subEntries, depth + 1);
          }
        }
      };
      scanLevel(drive, topEntries, 0);
    }
  } else {
    roots.push(path.join(os.homedir(), "World of Warcraft"));
    roots.push("/Applications/World of Warcraft");
  }

  return [...new Set(roots)];
}

function findSavedVariablesCandidates() {
  const roots = findWowInstallRoots();
  const found = [];

  function walk(dir, depth) {
    if (depth > 10) return;
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch (e) {
      return;
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (
        entry.isFile() &&
        entry.name === "WoWForeverTracker.lua" &&
        full.includes("SavedVariables")
      ) {
        found.push(full.replace(/\\/g, "/"));
      } else if (entry.isDirectory()) {
        walk(full, depth + 1);
      }
    }
  }

  for (const root of roots) {
    if (fs.existsSync(root)) walk(root, 0);
  }
  return [...new Set(found)];
}

// A friendly label like "Xeon-Mana (realm Whatever)" pulled out of the
// .../WTF/Account/<account>/<realm>/<character>/SavedVariables/... path.
// Note: this "realm" is really just the numeric realm-folder WoW uses on
// disk, not the addon's own realm name - it's only ever used for display,
// never sent to the website (see characterIdentityFromPath below for that).
function labelForPath(p) {
  const parts = p.split("/");
  const idx = parts.indexOf("SavedVariables");
  if (idx >= 2) {
    const character = parts[idx - 1];
    const realm = parts[idx - 2];
    return `${character} (${realm})`;
  }
  return p;
}

// Just the character-name folder, with no realm annotation - used as a
// fallback name when a file can no longer be read (e.g. it's been deleted
// since this path was first seen).
function characterNameFromPath(p) {
  const parts = p.split("/");
  const idx = parts.indexOf("SavedVariables");
  return idx >= 1 ? parts[idx - 1] : p;
}

// ---------------------------------------------------------------------
// Config - a shared site URL, plus one entry per character being watched
// ---------------------------------------------------------------------
function loadConfig() {
  if (!fs.existsSync(CONFIG_PATH)) return { siteUrl: "", accountToken: "", characters: [] };
  try {
    const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
    if (!Array.isArray(cfg.characters)) cfg.characters = [];
    if (!cfg.accountToken) cfg.accountToken = "";
    return cfg;
  } catch (e) {
    return { siteUrl: "", accountToken: "", characters: [] };
  }
}

function saveConfig(cfg) {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
}

function hasAnyCharacter(cfg) {
  return (
    cfg &&
    cfg.siteUrl &&
    cfg.accountToken &&
    Array.isArray(cfg.characters) &&
    cfg.characters.some((c) => c.enabled)
  );
}

// ---------------------------------------------------------------------
// The setup page
// ---------------------------------------------------------------------

// One character row's markup, shared between rows found by the disk scan
// and rows already configured but not found this time. The "Remove from
// website" button uses formaction/formmethod to submit to a different URL
// than the rest of the page's one big <form> - a plain nested <form> isn't
// valid HTML and browsers would mangle the layout, so this is the way to
// give one button in a form a different destination.
function renderCharRow(p, nameAttrSuffix, checked, extraLabel) {
  const escapedPath = p.replace(/"/g, "&quot;");
  const label = labelForPath(p) + (extraLabel ? ` ${extraLabel}` : "");
  const confirmText = `Remove ${labelForPath(p).replace(/'/g, "\\'")} from the website? This deletes it there completely (it'll reappear only if this PC syncs it again).`;
  return `<div class="char-row">
    <label class="char-check">
      <input type="checkbox" name="enabled_${nameAttrSuffix}" value="1" ${checked ? "checked" : ""}>
      <span class="char-label">${label}</span>
    </label>
    <input type="hidden" name="path_${nameAttrSuffix}" value="${escapedPath}">
    <button
      type="submit"
      formaction="/remove-character"
      formmethod="POST"
      name="removePath"
      value="${escapedPath}"
      class="remove-btn"
      onclick="return confirm('${confirmText}')"
    >Remove from website</button>
  </div>`;
}

function renderSetupPage(cfg, candidates, status) {
  status = status || {};
  const enabledByPath = {};
  for (const c of cfg.characters || []) enabledByPath[c.path] = c.enabled !== false;

  const rows = candidates
    .map((p, i) => {
      // Default a newly-found character to enabled, so people don't have
      // to hunt for a checkbox just to get their first character synced.
      const checked = p in enabledByPath ? enabledByPath[p] : true;
      return renderCharRow(p, i, checked, null);
    })
    .join("");

  // Any characters already configured whose path wasn't found by this
  // scan (different drive, addon not reinstalled yet, etc.) still get a
  // row so it isn't silently dropped.
  const extraRows = (cfg.characters || [])
    .filter((c) => !candidates.includes(c.path))
    .map((c, i) => renderCharRow(c.path, "extra" + i, c.enabled !== false, "(not found on this scan - keeping it)"))
    .join("");

  let banner = "";
  if (status.justSaved) {
    banner = `<div class="banner">Saved! You can close this tab.</div>`;
  } else if (status.removed) {
    banner = `<div class="banner">Removed ${status.removed} from the website and stopped tracking it here.</div>`;
  } else if (status.removeError) {
    banner = `<div class="banner banner-error">Couldn't remove that character: ${status.removeError}</div>`;
  }

  return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>WoW Forever Tracker - Setup</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; background: #1a1410; color: #eee0c0; max-width: 620px; margin: 40px auto; padding: 0 20px; }
  h1 { color: #d4af37; font-size: 22px; }
  h2 { color: #d4af37; font-size: 16px; margin-top: 32px; }
  p.lead { color: #cbbf9e; }
  label { display: block; margin-top: 20px; font-weight: 600; color: #eee0c0; }
  .hint { font-weight: 400; color: #9a8f74; font-size: 13px; }
  input[type=text] { width: 100%; box-sizing: border-box; padding: 10px; margin-top: 6px; border-radius: 6px; border: 1px solid #5a4a2a; background: #241c14; color: #eee0c0; font-size: 14px; }
  button { margin-top: 28px; padding: 12px 22px; background: #d4af37; color: #1a1410; font-weight: 700; border: none; border-radius: 6px; cursor: pointer; font-size: 15px; }
  button:hover { background: #e6c34f; }
  .banner { background: #22331f; border: 1px solid #4a7a3a; color: #bfe6ae; padding: 12px 16px; border-radius: 6px; margin-bottom: 20px; }
  .banner-error { background: #3a2020; border-color: #7a4a4a; color: #f0c8c8; }
  .char-row { border: 1px solid #3a2f1e; border-radius: 8px; padding: 14px; margin-top: 14px; background: #201810; }
  .char-label { font-weight: 600; margin-bottom: 4px; }
  .footer-note { margin-top: 30px; font-size: 12px; color: #7d7357; }
  .empty { color: #9a8f74; font-style: italic; }
  code { background: #241c14; padding: 1px 5px; border-radius: 4px; font-size: 12px; }
  .char-check { display: flex; align-items: center; gap: 10px; cursor: pointer; }
  .char-check input[type=checkbox] { width: 18px; height: 18px; flex-shrink: 0; }
  .char-check .char-label { margin: 0; font-weight: 600; }
  .remove-btn { margin-top: 10px; padding: 7px 14px; background: #3a2020; color: #f0c8c8; font-weight: 600; font-size: 12px; border: 1px solid #6a3a3a; border-radius: 6px; }
  .remove-btn:hover { background: #5a2a2a; }
</style>
</head>
<body>
  <h1>WoW Forever Tracker</h1>
  <p class="lead">One account token, one time. Tick which characters to watch - new ones you play show up here automatically and get created on the site the first time they sync.</p>
  ${banner}
  <form method="POST" action="/save">
    <label>Your website's address
      <div class="hint">Whatever URL you visit to see your character page.</div>
    </label>
    <input type="text" name="siteUrl" placeholder="https://your-site.vercel.app" value="${
      cfg.siteUrl || DEFAULT_SITE_URL
    }">

    <label>Your account sync token
      <div class="hint">From your account page on the website, "Account Auto-Sync Setup" panel - one token covers every character.</div>
    </label>
    <input type="text" name="accountToken" placeholder="Paste your account token here" value="${(
      cfg.accountToken || ""
    ).replace(/"/g, "&quot;")}">

    <h2>Characters found on this computer</h2>
    <p class="hint">Tick the ones you want tracked. Anything left unticked is never synced. "Remove from website" deletes that character there completely, not just here.</p>
    ${rows || `<p class="empty">None found yet - log into a character with the addon installed, play a bit, then log out (or /reload) once, and reopen this page.</p>`}
    ${extraRows}

    <button type="submit">Save</button>
  </form>
  <div class="footer-note">This page only runs on your own computer (localhost). Nothing is sent anywhere except to the site address above, and only for characters you've ticked.</div>
</body>
</html>`;
}

function startSetupServer(applyConfig) {
  const server = http.createServer(async (req, res) => {
    if (req.method === "GET" && (req.url === "/" || req.url.startsWith("/setup"))) {
      const cfg = loadConfig();
      const candidates = findSavedVariablesCandidates();
      const url = new URL(req.url, "http://127.0.0.1");
      const status = {
        justSaved: url.searchParams.get("saved") === "1",
        removed: url.searchParams.get("removed") || null,
        removeError: url.searchParams.get("removeError") || null,
      };
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      res.end(renderSetupPage(cfg, candidates, status));
    } else if (req.method === "POST" && req.url === "/save") {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", () => {
        const params = new URLSearchParams(body);
        const siteUrl = (params.get("siteUrl") || "").trim().replace(/\/$/, "");
        const accountToken = (params.get("accountToken") || "").trim();

        const pathKeys = [...params.keys()].filter((k) => k.startsWith("path_"));
        const characters = [];
        for (const pk of pathKeys) {
          const suffix = pk.slice("path_".length);
          const p = (params.get(pk) || "").trim();
          const enabled = params.get("enabled_" + suffix) === "1";
          if (p) {
            characters.push({ path: p, label: labelForPath(p), enabled });
          }
        }

        const cfg = { siteUrl, accountToken, characters, pollIntervalSeconds: 15 };
        saveConfig(cfg);

        // Redirect instead of rendering the result directly (the
        // "Post/Redirect/Get" pattern) - otherwise reloading the "Saved!"
        // page in your browser silently re-submits the same save, which
        // is what was causing repeated "Settings saved" notifications.
        res.writeHead(303, { Location: "/setup?saved=1" });
        res.end();

        applyConfig(cfg, "Settings saved - syncing is active.");
      });
    } else if (req.method === "POST" && req.url === "/remove-character") {
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", async () => {
        const params = new URLSearchParams(body);
        const removePath = (params.get("removePath") || "").trim();

        if (!removePath) {
          res.writeHead(303, {
            Location: "/setup?removeError=" + encodeURIComponent("No character was specified"),
          });
          res.end();
          return;
        }

        const cfg = loadConfig();
        if (!cfg.siteUrl || !cfg.accountToken) {
          res.writeHead(303, {
            Location:
              "/setup?removeError=" +
              encodeURIComponent("Fill in the site address and account token first, then Save"),
          });
          res.end();
          return;
        }

        // Reads the character's own export to get its real name/realm -
        // the same identity the website used when it first created this
        // character - so the right one gets matched and deleted.
        const { data } = readExport(removePath);
        const name = (data && data.basic && data.basic.name) || characterNameFromPath(removePath);
        const realm = (data && data.basic && data.basic.realm) || null;

        try {
          await postDeleteCharacter(cfg.siteUrl, cfg.accountToken, name, realm);
        } catch (e) {
          // Only treat this as "already gone, fine" when the SITE said, in
          // so many words, that it couldn't find that character - not for
          // any other 404, which more likely means the delete-character
          // endpoint itself isn't deployed yet (a generic Next.js 404 page
          // also comes back as status 404, but with different wording).
          // Anything else always surfaces as a real error instead of
          // silently pretending the removal worked.
          const looksLikeCharacterNotFound =
            e.statusCode === 404 && /could not find that character/i.test(e.message || "");
          if (!looksLikeCharacterNotFound) {
            res.writeHead(303, {
              Location: "/setup?removeError=" + encodeURIComponent(`${name}: ${e.message}`),
            });
            res.end();
            return;
          }
        }

        // Delete the character's own SavedVariables file too, so the row
        // actually disappears from "Characters found on this computer"
        // next time (that list is just a live disk scan - as long as the
        // file exists, it'll always be found again). This is just the
        // exported data the addon writes, not anything WoW itself needs -
        // deleting it never affects the character in-game, and if you
        // play that character again the addon just recreates the file.
        let fileDeleteError = null;
        try {
          fs.unlinkSync(removePath);
        } catch (e) {
          // Fine if it's already gone; anything else (permissions, file
          // in use) just means the row will keep reappearing, so it's
          // worth a mention in the banner below.
          if (e.code !== "ENOENT") fileDeleteError = e.message;
        }

        const existing = cfg.characters || [];
        if (fileDeleteError) {
          // Couldn't remove the file, so the row will keep coming back on
          // every scan - fall back to at least marking it disabled
          // (starts unticked) rather than leaving it enabled.
          const alreadyTracked = existing.some((c) => c.path === removePath);
          const characters = alreadyTracked
            ? existing.map((c) => (c.path === removePath ? { ...c, enabled: false } : c))
            : [...existing, { path: removePath, label: characterNameFromPath(removePath), enabled: false }];
          const updatedCfg = { ...cfg, characters };
          saveConfig(updatedCfg);
          applyConfig(updatedCfg, null);
          res.writeHead(303, {
            Location:
              "/setup?removeError=" +
              encodeURIComponent(
                `${name} was removed from the website, but its data file couldn't be deleted (${fileDeleteError}) so it'll still show up here, unticked.`
              ),
          });
          res.end();
          return;
        }

        // File's gone, so there's no reason to keep a row for this path at
        // all - the next scan simply won't find it.
        const updatedCfg = {
          ...cfg,
          characters: existing.filter((c) => c.path !== removePath),
        };
        saveConfig(updatedCfg);
        applyConfig(updatedCfg, null);
        lastMtimeByPath.delete(removePath);

        res.writeHead(303, { Location: "/setup?removed=" + encodeURIComponent(name) });
        res.end();
      });
    } else {
      res.writeHead(404);
      res.end("Not found");
    }
  });
  server.listen(SETUP_PORT, "127.0.0.1");
  return server;
}

// ---------------------------------------------------------------------
// Talking to the site
// ---------------------------------------------------------------------
const lastMtimeByPath = new Map();

function extractLuaString(text, key) {
  const marker = `["${key}"] = "`;
  const start = text.indexOf(marker);
  if (start === -1) return null;
  let i = start + marker.length;
  let out = "";
  while (i < text.length) {
    const ch = text[i];
    if (ch === "\\" && i + 1 < text.length) {
      out += text[i + 1];
      i += 2;
      continue;
    }
    if (ch === '"') return out;
    out += ch;
    i += 1;
  }
  return null;
}

function readExport(filePath) {
  let text;
  try {
    text = fs.readFileSync(filePath, "utf8");
  } catch (e) {
    return { error: "Could not read the file." };
  }
  const jsonText = extractLuaString(text, "json");
  if (!jsonText) {
    return { error: "No data yet on this character - just play a bit and log out (or /reload) once." };
  }
  try {
    return { data: JSON.parse(jsonText) };
  } catch (e) {
    return { error: "The data file looked corrupted - try again after your next /reload." };
  }
}

// Generic "POST some JSON, get JSON back (or a helpful error)" used for
// both syncing a character and deleting one - same server, same shape of
// response, just a different endpoint and payload.
function postJson(siteUrl, urlPath, payloadObj) {
  return new Promise((resolve, reject) => {
    const url = new URL(siteUrl + urlPath);
    const body = JSON.stringify(payloadObj);
    const lib = url.protocol === "https:" ? https : http;
    const req = lib.request(
      url,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) },
      },
      (res) => {
        let responseBody = "";
        res.on("data", (chunk) => (responseBody += chunk));
        res.on("end", () => {
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            resolve(responseBody);
          } else {
            // Try to pull out the site's own {"error": "..."} message so
            // the notification says WHY it failed, not just the status
            // code - much easier to act on without digging through logs.
            // Always keep the status code in the message too (as a
            // "HTTP <code> - " prefix) - otherwise an empty or non-JSON
            // response body (e.g. a route that isn't deployed, returning
            // a bare 404) shows up as a blank, useless error message.
            let reason = responseBody.slice(0, 200);
            try {
              const parsedBody = JSON.parse(responseBody);
              if (parsedBody && parsedBody.error) reason = parsedBody.error;
            } catch (e) {
              // Not JSON (e.g. an HTML error page) - fall back to the raw
              // text above.
            }
            const err = new Error(`HTTP ${res.statusCode}${reason ? " - " + reason : ""}`);
            err.statusCode = res.statusCode;
            reject(err);
          }
        });
      }
    );
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

function postSync(siteUrl, token, data) {
  // Tags every sync with this app's own version, so the website can record
  // it on your profile and show its own "update available" banner there -
  // this app no longer checks or nags about updates itself (see the note
  // near TRAY_VERSION above).
  return postJson(siteUrl, "/api/sync", { token, data, trayVersion: TRAY_VERSION });
}

function postDeleteCharacter(siteUrl, token, name, realm) {
  return postJson(siteUrl, "/api/delete-character", { token, name, realm });
}

async function syncOneCharacter(siteUrl, accountToken, character, force) {
  if (!character.enabled) return;

  let stat;
  try {
    stat = fs.statSync(character.path);
  } catch (e) {
    if (force) notify("WoW Forever Tracker", `Can't find ${character.label}'s file - check Settings.`);
    return;
  }

  const last = lastMtimeByPath.get(character.path) || 0;
  if (!force && stat.mtimeMs === last) return;
  lastMtimeByPath.set(character.path, stat.mtimeMs);

  const { data, error } = readExport(character.path);
  if (error) {
    if (force) notify("WoW Forever Tracker", `${character.label}: ${error}`);
    return;
  }

  try {
    await postSync(siteUrl, accountToken, data);
    // Only confirm success out loud when this was a manual "Sync now" click
    // (force = true). The normal background sync runs every 15 seconds for
    // every character you've ticked, so popping a notification + sound on
    // every single one of those would mean a constant stream of "Synced!"
    // toasts all evening - noisy for something that's supposed to be
    // invisible when it's working. A failure is still worth interrupting
    // you for either way, since that's the one case you'd actually want to
    // know about and act on.
    if (force) notify("WoW Forever Tracker", `Synced ${character.label}!`);
  } catch (e) {
    notify("WoW Forever Tracker", `${character.label} sync failed: ${e.message}`);
  }
}

async function checkAndSync(getCfg, force) {
  const cfg = getCfg();
  if (!hasAnyCharacter(cfg)) {
    if (force) notify("WoW Forever Tracker", "Finish Settings first (open it from the tray menu).");
    return;
  }
  for (const character of cfg.characters) {
    await syncOneCharacter(cfg.siteUrl, cfg.accountToken, character, force);
  }
}

// ---------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------
async function main() {
  if (!acquireLock()) {
    // Another copy is already running - don't start a second tray icon
    // or a second sync loop, just point the user at the running one.
    openInBrowser(`http://127.0.0.1:${SETUP_PORT}/setup`);
    process.exit(0);
  }
  process.on("exit", releaseLock);
  process.on("SIGINT", () => process.exit(0));
  process.on("SIGTERM", () => process.exit(0));

  let config = loadConfig();
  const getCfg = () => config;

  // Used by both /save and /remove-character to update the config this
  // running process is using, without either of them needing to reach
  // into this function's local variables directly.
  function applyConfig(newConfig, message) {
    config = newConfig;
    lastMtimeByPath.clear();
    if (message) notify("WoW Forever Tracker", message);
  }

  const server = startSetupServer(applyConfig);

  if (!hasAnyCharacter(config)) {
    openInBrowser(`http://127.0.0.1:${SETUP_PORT}/setup`);
  }

  const quit = () => {
    try {
      server.close();
    } catch (e) {}
    process.exit(0);
  };

  if (SysTray) {
    let systray;
    try {
      systray = new SysTray({
        menu: {
          icon: TRAY_ICON_BASE64,
          title: "WoW Forever Tracker",
          tooltip: "WoW Forever Tracker",
          items: [
            { title: "Sync now", tooltip: "", checked: false, enabled: true },
            { title: "Settings", tooltip: "", checked: false, enabled: true },
            { title: "Open my character page", tooltip: "", checked: false, enabled: true },
            { title: "Quit", tooltip: "", checked: false, enabled: true },
          ],
        },
        debug: false,
        copyDir: true,
      });

      systray.onClick((action) => {
        if (action.seq_id === 0) {
          checkAndSync(getCfg, true);
        } else if (action.seq_id === 1) {
          openInBrowser(`http://127.0.0.1:${SETUP_PORT}/setup`);
        } else if (action.seq_id === 2) {
          if (config.siteUrl) openInBrowser(config.siteUrl);
          else notify("WoW Forever Tracker", "Finish Settings first.");
        } else if (action.seq_id === 3) {
          try {
            systray.kill();
          } catch (e) {}
          quit();
        }
      });
    } catch (e) {
      notify(
        "WoW Forever Tracker",
        "Running without a tray icon (couldn't start it) - it's still syncing in the background."
      );
    }
  } else {
    notify(
      "WoW Forever Tracker",
      "Running in the background (tray icon unavailable) - open Settings any time at http://127.0.0.1:47891/setup"
    );
  }

  checkAndSync(getCfg, false);
  setInterval(() => checkAndSync(getCfg, false), 15000);
}

main();
