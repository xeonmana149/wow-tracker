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
  addon: "1.8.3",
  tray: "1.2.0",
};

// Wherever people should go to grab the update. The tray app still points
// at the human-facing Downloads page (it's only ever linked for someone to
// click) - but the addon needs a DIRECT file link, because the tray app's
// own auto-update check (main.js's checkForAddonUpdate) fetches this value
// from /api/version and downloads it programmatically, not a page a person
// reads. Keep this in sync with whatever the actual filename is under
// public/downloads/ in the website project.
export const DOWNLOAD_URLS = {
  addon: "/downloads/WoWForeverTrackerAddon.zip",
  // Evergreen GitHub link: redirects to the newest release's asset with
  // this exact filename. Only works because tray-electron/package.json's
  // nsis.artifactName is fixed to "WoWForeverTrackerSetup.exe" (no version
  // in the name) - if that ever changes, this URL breaks.
  tray: "https://github.com/xeonmana149/wow-tracker/releases/latest/download/WoWForeverTrackerSetup.exe",
};