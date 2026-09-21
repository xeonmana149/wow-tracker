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
  addon: "1.2.0",
  tray: "1.0.0",
};

// Wherever people should go to grab the update - both point at the same
// Downloads page for now since that's where both live.
export const DOWNLOAD_URLS = {
  addon: "/download",
  tray: "/download",
};g