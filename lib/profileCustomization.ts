import { wowIconUrl } from "./icons";

// Account profile customization (2026-09-29, extended same day: "like with
// achievements im gonna make custom art for those things that website users
// can choose between"). So this is NOT per-user uploads or pasted URLs -
// it's the same pattern as the achievement badges' local art
// (lib/achievementBadges.ts / lib/badgeFrames.ts): a small fixed picker of
// options, most pointing at real game icons or CSS presets today, and any
// of them upgradable to Jordan's own custom art later just by dropping a
// PNG in /public and adding one line below - no other code changes needed.
//
//   - Account icon art -> save as /public/profile-icons/<slug>.png and add
//     an AVATAR_ICON_OPTIONS entry with that slug as `localSlug`. Source
//     art should be square, at least AVATAR_ICON_SRC_SIZE_PX (256x256)px -
//     it's displayed as an 88x88px circle (see .crest in theme.css), so
//     keep the subject centered; the corners get cropped off.
//   - Banner art -> save as /public/profile-banners/<slug>.png and add a
//     BANNER_STYLE_OPTIONS entry with that slug as `localSlug`. Source art
//     should be BANNER_IMAGE_SRC_WIDTH_PX x BANNER_IMAGE_SRC_HEIGHT_PX
//     (1200x240px, 5:1 landscape - a compact banner strip, not a full-height
//     hero image; the header box is a fixed 220px tall - see .account-banner
//     in theme.css - so keep the important part of the composition centered
//     vertically, since some cropping on very narrow/wide screens is normal
//     for a responsive banner).
//
// `key` is what actually gets stored in profiles.avatar_icon /
// profiles.banner_style, so never rename an existing option's `key` once
// it's shipped - that would silently reset anyone who already picked it
// back to the fallback. Add new options, don't rename old ones.
//
// 2026-09-30 - Jordan's decided against using real WoW icons for account
// icons at all ("If I can avoid using wow icons I would prefer that") -
// these are meant to become another achievement-unlock collection down the
// line (see the "unlocking icons from achievements" conversation), fully
// custom art throughout rather than a mix. The starter wowIcon-based set is
// removed; AVATAR_ICON_OPTIONS now only ever holds localSlug (custom art)
// entries, added one at a time as art gets made. avatarIconSrc()/wowIcon
// stay supported on the type for now in case a placeholder is ever wanted
// again, but nothing currently uses that path.
export const AVATAR_ICON_SRC_SIZE_PX = 256;
export const BANNER_IMAGE_SRC_WIDTH_PX = 1200;
export const BANNER_IMAGE_SRC_HEIGHT_PX = 240;

export type AvatarIconOption = {
  key: string;
  label: string;
  wowIcon?: string; // real WoW icon name, resolved via wowIconUrl() - legacy fallback, not used by any current option
  localSlug?: string; // custom art at /public/profile-icons/<slug>.png - wins over wowIcon if both are set
};

// Custom-art account icons. Add more the same way - drop the PNG in
// /public/profile-icons/ and add a line here.
export const AVATAR_ICON_OPTIONS: AvatarIconOption[] = [
  { key: "orc-shaman-female", label: "Orc Shaman (Female)", localSlug: "orc-shaman-female" },
  { key: "orc-shaman-male", label: "Orc Shaman (Male)", localSlug: "orc-shaman-male" },
  { key: "orc-warrior-female", label: "Orc Warrior (Female)", localSlug: "orc-warrior-female" },
  { key: "orc-warrior-male", label: "Orc Warrior (Male)", localSlug: "orc-warrior-male" },
  { key: "troll-shaman-male", label: "Troll Shaman (Male)", localSlug: "troll-shaman-male" },
  { key: "undead-paladin-female", label: "Undead Paladin (Female)", localSlug: "undead-paladin-female" },
  { key: "undead-paladin-male", label: "Undead Paladin (Male)", localSlug: "undead-paladin-male" },
  { key: "male-skyborne-hunter", label: "Skyborne Hunter (Male)", localSlug: "male-skyborne-hunter" },
];

export function avatarIconSrc(option: AvatarIconOption): string {
  if (option.localSlug) return `/profile-icons/${option.localSlug}.png`;
  return wowIconUrl(option.wowIcon ?? "inv_misc_questionmark");
}

export function findAvatarIconOption(key: string | null): AvatarIconOption | undefined {
  return AVATAR_ICON_OPTIONS.find((o) => o.key === key);
}

export type BannerOption = {
  key: string;
  label: string;
  localSlug?: string; // custom art at /public/profile-banners/<slug>.png - wins over the CSS gradient preset below if set
};

// 2026-09-30 - swapped out the character-portrait banners and the 5 flat
// CSS-gradient color presets ("the boring colour ones") for a set of
// WoW zone/scenery landscape banners instead. "parchment" stays as the one
// non-custom-art option - it's the same neutral default background used
// everywhere else on the site (character pages, etc.), not a color theme,
// so it's kept as the fallback for anyone who hasn't picked art.
export const BANNER_STYLE_OPTIONS: BannerOption[] = [
  { key: "parchment", label: "Parchment (default)" },
  // Zone banners - files go at /public/profile-banners/<slug>.png, cropped
  // to the recommended 1200x240 (5:1).
  { key: "barrens", label: "The Barrens", localSlug: "barrens" },
  { key: "elwynn-forest", label: "Elwynn Forest", localSlug: "elwynn-forest" },
  { key: "night-elf-grove", label: "Night Elf Grove", localSlug: "night-elf-grove" },
  { key: "river-watermill", label: "River Watermill", localSlug: "river-watermill" },
  { key: "shipwreck-coast", label: "Shipwreck Coast", localSlug: "shipwreck-coast" },
  { key: "westfall", label: "Westfall", localSlug: "westfall" },
  { key: "hyjal-roots", label: "Hyjal Roots", localSlug: "hyjal-roots" },
  { key: "distant-hyjal", label: "Distant Hyjal", localSlug: "distant-hyjal" },
  { key: "dun-morogh", label: "Dun Morogh", localSlug: "dun-morogh" },
  // 2026-10-03 batch - art already dropped in /public/profile-banners/.
  { key: "duskwood", label: "Duskwood", localSlug: "duskwood" },
  { key: "hillsbrad-foothills", label: "Hillsbrad Foothills", localSlug: "hillsbrad-foothills" },
  { key: "shimmering-flats", label: "Shimmering Flats", localSlug: "shimmering-flats" },
  { key: "zephras-isle", label: "Zephras Isle", localSlug: "zephras-isle" },
];

export function findBannerOption(key: string | null): BannerOption | undefined {
  return BANNER_STYLE_OPTIONS.find((o) => o.key === key);
}

// null when this option has no custom art yet (use the CSS gradient class
// from bannerClassName() instead).
export function bannerImageSrc(option: BannerOption | undefined): string | null {
  return option?.localSlug ? `/profile-banners/${option.localSlug}.png` : null;
}

export function bannerClassName(style: string | null): string {
  const match = findBannerOption(style);
  if (!match) return "parchment";
  if (match.localSlug) return "profile-banner-custom";
  return match.key !== "parchment" ? `profile-banner-${match.key}` : "parchment";
}

export const MOTTO_MAX_LENGTH = 140;