// Account profile customization (2026-09-29, Jordan's request: "an edit
// profile section... change your account icon, your account page banner,
// add like a motto"). There's no file-upload/storage system anywhere in
// this project yet, so rather than build one just for this, both the icon
// and the banner are curated picks - a real WoW icon name (resolved through
// wowIconUrl(), same mechanism the account badges already use) for the
// avatar, and a named CSS gradient preset (defined in theme.css) for the
// banner. If Jordan wants actual image uploads later, that's a bigger
// follow-up (needs Supabase Storage wired up), not something to fake here.

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
