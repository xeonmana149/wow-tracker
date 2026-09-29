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

export const AVATAR_ICON_SRC_SIZE_PX = 256;
export const BANNER_IMAGE_SRC_WIDTH_PX = 1200;
export const BANNER_IMAGE_SRC_HEIGHT_PX = 240;

export type AvatarIconOption = {
  key: string;
  label: string;
  wowIcon?: string; // real WoW icon name, resolved via wowIconUrl()
  localSlug?: string; // custom art at /public/profile-icons/<slug>.png - wins over wowIcon if both are set
};

// A small, thematically varied starter set of real WoW icons - general/
// class-neutral rather than tied to one class or profession, since this is
// an ACCOUNT icon, not a character one. Swap any of these to custom art by
// giving it a `localSlug`, or just add new entries alongside them.
export const AVATAR_ICON_OPTIONS: AvatarIconOption[] = [
  { key: "achievement_general", label: "General", wowIcon: "achievement_general" },
  { key: "achievement_reputation_01", label: "Reputation", wowIcon: "achievement_reputation_01" },
  { key: "inv_misc_coin_06", label: "Coin", wowIcon: "inv_misc_coin_06" },
  { key: "achievement_boss_illidan", label: "Illidan", wowIcon: "achievement_boss_illidan" },
  { key: "spell_holy_holybolt", label: "Holy Bolt", wowIcon: "spell_holy_holybolt" },
  { key: "spell_nature_lightning", label: "Lightning", wowIcon: "spell_nature_lightning" },
  { key: "ability_rogue_shadowstep", label: "Shadowstep", wowIcon: "ability_rogue_shadowstep" },
  { key: "achievement_pvp_a_a", label: "PvP", wowIcon: "achievement_pvp_a_a" },
  { key: "inv_sword_04", label: "Sword", wowIcon: "inv_sword_04" },
  { key: "inv_staff_13", label: "Staff", wowIcon: "inv_staff_13" },
  { key: "achievement_dungeon_bossmaster", label: "Boss Master", wowIcon: "achievement_dungeon_bossmaster" },
  { key: "inv_misc_head_dragon_01", label: "Dragon", wowIcon: "inv_misc_head_dragon_01" },
  // Custom-art icons go here once they exist, e.g.:
  // { key: "phoenix", label: "Phoenix", localSlug: "phoenix" },
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

// The 5 CSS-gradient presets from theme.css, plus the default. Swap any of
// these to custom art by giving it a `localSlug`, or add new entries.
export const BANNER_STYLE_OPTIONS: BannerOption[] = [
  { key: "parchment", label: "Parchment (default)" },
  { key: "midnight", label: "Midnight" },
  { key: "ember", label: "Ember" },
  { key: "verdant", label: "Verdant" },
  { key: "royal", label: "Royal" },
  { key: "shadow", label: "Shadow" },
  // Custom-art banners (2026-09-29) - files go at
  // /public/profile-banners/<slug>.png. The two Horde ones arrived at
  // 1983x793 and 2172x724 (2.5:1 / 3:1) - neither matches the 5:1 box, so
  // both got cropped+resized down to the recommended 1200x240 before being
  // added here (kept each character's face and the horizon/sun in frame).
  { key: "silverpine-paladin", label: "Silverpine Paladin", localSlug: "silverpine-paladin" },
  { key: "orgrimmar-warrior", label: "Orgrimmar Warrior", localSlug: "orgrimmar-warrior" },
  { key: "durotar-shaman", label: "Durotar Shaman", localSlug: "durotar-shaman" },
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