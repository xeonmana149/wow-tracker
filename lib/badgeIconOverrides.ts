import type { SupabaseClient } from "@supabase/supabase-js";

// Every badge's icon can be overridden at runtime via the badge_icons
// table, edited from the /dev/badges tester page, without touching code
// or redeploying. Keys match how each badge is identified elsewhere: an
// AchievementKind ("max_level", ...), "gold:Bronze"/"gold:Silver"/
// "gold:Gold", "epic_gear", "created_date", or an AccountAchievementKind
// ("class_collector", ...).
export type BadgeIconOverrides = Record<string, string>;

export async function loadBadgeIconOverrides(
  supabase: SupabaseClient
): Promise<BadgeIconOverrides> {
  const { data } = await supabase.from("badge_icons").select("key, icon");
  const map: BadgeIconOverrides = {};
  for (const row of (data ?? []) as { key: string; icon: string }[]) {
    map[row.key] = row.icon;
  }
  return map;
}

// Every renderer (CharacterCard, AccountBadges, the tester page itself)
// calls this instead of reading a badge's coded-in icon directly, so an
// override - if one exists for that key - always wins.
export function resolvedIcon(
  overrides: BadgeIconOverrides,
  key: string,
  defaultIcon: string
): string {
  return overrides[key] ?? defaultIcon;
}
