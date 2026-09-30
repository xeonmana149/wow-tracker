// The single source of truth for "what's the current version of each
// piece". Bump the relevant number here and redeploy whenever you ship a
// new build of the addon or the desktop sync app - nothing else needs to
// change, both check against this automatically from then on.
//
// These are just opaque strings compared for equality, not real semver -
// fine for a small friend group where only you ever publish a version, but
// it does mean a typo'd or reverted number here won't be caught, just
// treated as "different, so out of date" by whoever's checking.
export const LATEST_VERSIONS = {
  addon: "1.8.9",
  tray: "2.2.4",
};

// Wherever people should go to grab the update. Both now point at GitHub
// Releases via an evergreen link (redirects to the newest release's asset
// with this exact filename) rather than a file sitting in the website's own
// public/downloads/ folder - that used to mean every addon update needed
// TWO separate deploys kept in sync (bump LATEST_VERSIONS.addon here, AND
// separately remember to drop a rebuilt zip into the website project and
// redeploy it) - miss the second step and the tray app's auto-update 404s,
// which is exactly what happened 2026-09-27. Now shipping a new addon
// version is just: rebuild WoWForeverTrackerAddon.zip, attach it to the
// SAME GitHub release the tray installer publishes to (e.g. via
// `gh release upload <tag> WoWForeverTrackerAddon.zip`, run right after
// electron-builder's publish step), and bump LATEST_VERSIONS.addon below -
// no website redeploy needed for the addon at all anymore.
export const DOWNLOAD_URLS = {
  // Only works because the release actually has an asset with this EXACT
  // filename attached - electron-builder does that automatically for the
  // tray installer (nsis.artifactName in tray-electron/package.json), but
  // for the addon zip that upload is a manual (or scripted) extra step you
  // do yourself - see the comment above.
  addon: "https://github.com/xeonmana149/wow-tracker/releases/latest/download/WoWForeverTrackerAddon.zip",
  tray: "https://github.com/xeonmana149/wow-tracker/releases/latest/download/WoWForeverTrackerSetup.exe",
};