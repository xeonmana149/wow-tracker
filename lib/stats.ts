export type StatDef = {
  label: string;
  keys: string[]; // one key for a normal stat, two (min, max) for a damage range
  suffix?: string; // shown after the number, like %
  start?: number; // the value before anything is entered
  signed?: boolean; // can be negative, like hit chance against higher-level enemies
};

export const STAT_GROUPS: { title: string; stats: StatDef[] }[] = [
  {
    title: "General",
    stats: [
      { label: "Max Health", keys: ["max_health"] },
      { label: "Max Mana", keys: ["max_mana"] },
      { label: "Movement Speed", keys: ["movement_speed"], suffix: "%", start: 100 },
    ],
  },
  {
    title: "Primary Attributes",
    stats: [
      { label: "Strength", keys: ["strength"] },
      { label: "Agility", keys: ["agility"] },
      { label: "Intellect", keys: ["intellect"] },
      { label: "Stamina", keys: ["stamina"] },
      { label: "Spirit", keys: ["spirit"] },
    ],
  },
  {
    title: "Weapons",
    stats: [
      { label: "Main Hand", keys: ["main_hand_min", "main_hand_max"] },
      { label: "Attack Power", keys: ["attack_power"] },
      { label: "Crit Strike", keys: ["crit_strike"], suffix: "%" },
      { label: "Hit vs equal level", keys: ["hit_equal"], suffix: "%", signed: true },
      { label: "Hit vs raid boss", keys: ["hit_boss"], suffix: "%", signed: true },
    ],
  },
  {
    title: "Defense",
    stats: [
      { label: "Defense", keys: ["defense"] },
      { label: "Dodge", keys: ["dodge"], suffix: "%" },
      { label: "Parry", keys: ["parry"], suffix: "%" },
      { label: "Armor", keys: ["armor"] },
    ],
  },
  {
    title: "Resistances",
    stats: [
      { label: "Arcane", keys: ["res_arcane"] },
      { label: "Fire", keys: ["res_fire"] },
      { label: "Frost", keys: ["res_frost"] },
      { label: "Nature", keys: ["res_nature"] },
      { label: "Shadow", keys: ["res_shadow"] },
    ],
  },
];

export const ALL_KEYS: string[] = STAT_GROUPS.flatMap((g) =>
  g.stats.flatMap((s) => s.keys)
);

// The value each stat has before anything has been entered
export const START_VALUES: Record<string, number> = {};
for (const group of STAT_GROUPS) {
  for (const stat of group.stats) {
    for (const key of stat.keys) {
      START_VALUES[key] = stat.start ?? 0;
    }
  }
}

// Stats that are allowed to go below zero
export const SIGNED_KEYS = new Set<string>(
  STAT_GROUPS.flatMap((g) => g.stats.filter((s) => s.signed).flatMap((s) => s.keys))
);