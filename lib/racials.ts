// Source: Mobalytics, "WoW Forever: All Racial Abilities" (updated 18 Sep 2026).
// These are the announced abilities and may change during the beta.

export type Racial = {
  name: string;
  kind: "Active" | "Passive";
  description: string;
};

export const RACIALS: Record<string, Racial[]> = {
  Human: [
    { name: "Will to Survive", kind: "Active", description: "Breaks free of stun effects." },
    { name: "Perception", kind: "Active", description: "Lets you see stealthed enemies for 20 seconds." },
    { name: "Sword Specialization", kind: "Passive", description: "Using swords adds 2% to spell and ability crit chance." },
    { name: "The Human Spirit", kind: "Passive", description: "Spirit is 5% higher." },
  ],
  Dwarf: [
    { name: "Stoneform", kind: "Active", description: "Immune to bleeds, poisons and diseases, and takes less physical damage, for 8 seconds." },
    { name: "Find Treasure", kind: "Active", description: "Tracks treasure chests close by." },
    { name: "Mace Specialization", kind: "Passive", description: "Using maces adds 1% to spell and ability crit chance." },
    { name: "Big Game Hunter", kind: "Passive", description: "Deal 5% more damage to beasts." },
  ],
  "Night Elf": [
    { name: "Elune's Light", kind: "Active", description: "Crit chance up 10% for 15 seconds." },
    { name: "Shadowmeld", kind: "Active", description: "Stealth while you stand still." },
    { name: "Quickness", kind: "Passive", description: "1% more dodge and 2% more run speed." },
    { name: "Wisp Spirit", kind: "Passive", description: "Run 75% faster while dead." },
  ],
  Gnome: [
    { name: "Escape Artist", kind: "Active", description: "Short immunity to roots and snares." },
    { name: "Eureka!", kind: "Active", description: "Your next three spells or abilities cost less and deal or heal 10% more." },
    { name: "Expansive Mind", kind: "Passive", description: "Max mana, rage or energy is 5% higher." },
    { name: "Engineering Specialization", kind: "Passive", description: "Engineering devices are more reliable." },
  ],
  "Alliance Skyborne": [
    { name: "Walk on Air", kind: "Active", description: "Glide downward through the air for 10 seconds." },
    { name: "Read Ley Line", kind: "Active", description: "Activates a ley line that doubles health and mana regeneration." },
    { name: "Wind Blessed", kind: "Passive", description: "Melee, ranged and spell haste up 1%." },
    { name: "Elemental Insight", kind: "Passive", description: "Deal 5% more damage to elementals." },
  ],
  Orc: [
    { name: "Blood Fury", kind: "Active", description: "Attack power and spell power up 10% for 15 seconds." },
    { name: "Shatter Curse", kind: "Active", description: "Immune to curses and banes, and takes less magic damage, for 8 seconds." },
    { name: "Axe Specialization", kind: "Passive", description: "Using axes adds 1% to spell and ability crit chance." },
    { name: "Hardiness", kind: "Passive", description: "Stuns on you last 20% shorter." },
  ],
  Undead: [
    { name: "Will of the Forsaken", kind: "Active", description: "Removes charm, fear and sleep effects." },
    { name: "Cannibalize", kind: "Active", description: "Eat a corpse to restore 35% health and mana over time." },
    { name: "Underwater Breathing", kind: "Passive", description: "Hold your breath underwater 300% longer." },
    { name: "Touch of the Grave", kind: "Passive", description: "Your attacks sometimes drain health." },
  ],
  Tauren: [
    { name: "War Stomp", kind: "Active", description: "Stuns nearby enemies for 2 seconds." },
    { name: "Cultivation", kind: "Active", description: "Sprouts extra herbs that can be picked without Herbalism." },
    { name: "Plainsrunning", kind: "Passive", description: "Movement speed builds the longer you keep moving." },
    { name: "Endurance", kind: "Passive", description: "5% more total health and 1% more hit chance." },
  ],
  Troll: [
    { name: "Berserking", kind: "Active", description: "Casting and attack speed up 10% for 10 seconds." },
    { name: "Rapid Regeneration", kind: "Active", description: "Regenerates 50% of max health over time." },
    { name: "Beast Slaying", kind: "Passive", description: "Deal 5% more damage to beasts." },
    { name: "Regeneration", kind: "Passive", description: "10% of your health regeneration keeps working in combat." },
  ],
  "Horde Skyborne": [
    { name: "Walk on Air", kind: "Active", description: "Glide downward through the air for 10 seconds." },
    { name: "Skysight", kind: "Active", description: "An elemental blessing that gives 10% more run speed." },
    { name: "Wind Blessed", kind: "Passive", description: "Melee, ranged and spell haste up 1%." },
    { name: "Elemental Insight", kind: "Passive", description: "Deal 5% more damage to elementals." },
  ],
};