// Account profile customization (2026-09-29, Jordan's request: "an edit
// profile section... change your account icon, your account page banner,
// add like a motto"). There's no file-upload/storage system anywhere in
// this project yet, so rather than build a Supabase Storage pipeline just
// for this, custom art is supplied as an image URL (host it anywhere -
// Imgur, Discord CDN, your own site - and paste the link in) instead of an
// upload button. The curated WoW icon / gradient presets stay as the
// no-effort default; a pasted URL simply takes priority when present. True
// file uploads are still a bigger follow-up if wanted later.
//
// Recommended source-art sizes for a crisp, uncropped result:
//  - Avatar icon: square, at least 256x256px. Displayed as an 88x88px
//    circle (see .crest in theme.css), so keep the important part of the
//    image centered - the corners get cropped off by the circle mask.
//  - Banner: 1200x300px (4:1 landscape). Rendered with
//    background-size: cover, so it always fills the header without
//    stretching, but a taller/narrower image will get cropped top/bottom
//    or left/right to fit that ratio.
export const AVATAR_IMAGE_RECOMMENDED_SIZE_PX = 256;
export const BANNER_IMAGE_RECOMMENDED_WIDTH_PX = 1200;
export const BANNER_IMAGE_RECOMMENDED_HEIGHT_PX = 300;

// A a small, thematically varied set of real WoW icons - general/class-
// neutral rather than tied to one class or profession, since this is an
// ACCOUNT icon, not a character one.
export const AVATAR_ICON_OPTIONS: string[] = [
  "achievement_general",
  "achievement_reputation_01",
  "inv_misc_coin_06",
  "achievement_boss_illidan",
  "spell_holy_holybolt",
  "spell_nature_lightning",
  "ability_rogue_shadowstep",
  "achievement_pvp_a_a",
  "inv_sword_04",
  "inv_staff_13",
  "achievement_dungeon_bossmaster",
  "inv_misc_head_dragon_01",
];

export type BannerStyle = "parchment" | "midnight" | "ember" | "verdant" | "royal" | "shadow";

export const BANNER_STYLE_OPTIONS: { key: BannerStyle; label: string }[] = [
  { key: "parchment", label: "Parchment (default)" },
  { key: "midnight", label: "Midnight" },
  { key: "ember", label: "Ember" },
  { key: "verdant", label: "Verdant" },
  { key: "royal", label: "Royal" },
  { key: "shadow", label: "Shadow" },
];

export function bannerClassName(style: string | null): string {
  const match = BANNER_STYLE_OPTIONS.find((o) => o.key === style);
  return match && match.key !== "parchment" ? `profile-banner-${match.key}` : "parchment";
}

export const MOTTO_MAX_LENGTH = 140;