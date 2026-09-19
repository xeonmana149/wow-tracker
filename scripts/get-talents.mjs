// Downloads the WoW Forever talent data and icons from talentsforever.com.
// Data: Talents Forever, CC BY 4.0. Icons and tooltip text belong to Blizzard Entertainment.
import { mkdir, writeFile, access } from "node:fs/promises";

const CLASSES = ["warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid"];
const BASE = "https://talentsforever.com";
const FAN_SITE = "https://wowforevertalent.com";
const FALLBACK = "https://wow.zamimg.com/images/wow/icons/large";
const DATA_DIR = "lib/talent-data";
const ICON_DIR = "public/talent-icons";

// Icons we need that aren't part of the talent data
const RACE_ICONS = [
  "race_human_male",
  "race_dwarf_male",
  "race_nightelf_male",
  "race_gnome_male",
  "race_skyborne",
  "race_orc_male",
  "race_scourge_male",
  "race_tauren_male",
  "race_troll_male",
];

const PROFESSION_ICONS = [
  "trade_alchemy",
  "trade_blacksmithing",
  "trade_engraving",
  "trade_engineering",
  "trade_herbalism",
  "trade_leatherworking",
  "trade_mining",
  "inv_misc_pelt_wolf_01",
  "trade_tailoring",
  "inv_misc_food_15",
  "spell_holy_sealofsalvation",
  "trade_fishing",
];

// The legacy perk and tree pictures from wowforevertalent.com/legacy.
// Keep this list in step with LEGACY_PERK_ICONS and LEGACY_TREE_ICONS in lib/legacy.ts.
const LEGACY_ICONS = [
  "inv_misc_map_01",
  "inv_misc_coin_01",
  "trade_engineering",
  "spell_shadow_detectlesserinvisibility",
  "spell_nature_sleep",
  "ability_marksmanship",
  "ability_hunter_huntervswild",
  "inv_fishingchair",
  "achievement_guild_ridelikethewind",
  "inv_misc_bandage_05",
  "achievement_bg_winwsg",
  "inv_misc_food_64",
  "spell_misc_emotionhappy",
  "spell_shadow_deadofnight",
  "inv_misc_candle_02",
  "inv_misc_armorkit_17",
  "inv_scroll_03",
  "achievement_profession_chefhat",
  "inv_misc_pocketwatch_03",
  "inv_misc_coin_06",
  "inv_misc_book_08",
  "inv_misc_bag_18",
  "racial_dwarf_findtreasure",
  "inv_misc_basket_04",
];

// Ranks come as a list for some talents and as { "1": text } for others. Make them all the second kind.
function normalizeDesc(desc) {
  if (Array.isArray(desc)) {
    const out = {};
    desc.forEach((text, i) => {
      out[String(i + 1)] = text;
    });
    return out;
  }
  return desc ?? {};
}

function clean(text) {
  return String(text)
    .replace(/<!--.*?-->/g, "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .trim();
}

await mkdir(DATA_DIR, { recursive: true });
await mkdir(ICON_DIR, { recursive: true });

const icons = new Set([...RACE_ICONS, ...PROFESSION_ICONS, ...LEGACY_ICONS]);

// The class crests used on the character and friends pages
for (const c of CLASSES) icons.add("class_" + c);

const raceIcons = {};
const abilityIcons = {};
let legacy = null;

for (const cls of CLASSES) {
  const res = await fetch(`${BASE}/data/${cls}.json`);
  if (!res.ok) {
    console.error(`Could not download ${cls} (status ${res.status})`);
    continue;
  }
  const raw = await res.json();

  const trees = raw.talents.trees.map((tree) => {
    icons.add(tree.icon);
    return {
      name: tree.name,
      icon: tree.icon,
      talents: tree.talents.map((t) => {
        icons.add(t.icon);
        const desc = {};
        for (const [rank, text] of Object.entries(normalizeDesc(t.desc))) {
          desc[rank] = clean(text);
        }
        return {
          name: t.name,
          max: t.max,
          row: t.row,
          col: t.col,
          passive: t.passive !== false,
          icon: t.icon,
          desc,
          complete: !!t.complete,
          req: t.req ?? null,
          reqText: t.reqText ? clean(t.reqText) : null,
          cost: t.cost ? clean(t.cost) : null,
          scaleIdx: t.scaleIdx ?? [],
          isNew: t.classic?.status === "new",
        };
      }),
    };
  });

  await writeFile(
    `${DATA_DIR}/${cls}.json`,
    JSON.stringify({ class: raw.class, generated: raw.generated, trees })
  );
  const count = trees.reduce((n, t) => n + t.talents.length, 0);
  console.log(`${raw.class}: ${count} talents`);

  // Race and racial pictures. Every class file lists the races that can be that class.
  for (const faction of ["Alliance", "Horde"]) {
    for (const r of raw.racials?.[faction] ?? []) {
      const raceName = String(r.race).startsWith("Skyborne") ? `${faction} Skyborne` : r.race;
      raceIcons[raceName] = r.icon;
      icons.add(r.icon);
      for (const ability of r.abilities ?? []) {
        abilityIcons[ability[0]] = ability[2];
        icons.add(ability[2]);
      }
    }
  }

  if (!legacy && raw.legacy) legacy = raw.legacy;
}

await writeFile(
  `${DATA_DIR}/_icons.json`,
  JSON.stringify({ races: raceIcons, abilities: abilityIcons })
);

if (legacy) {
  for (const tree of legacy.trees ?? []) {
    icons.add(tree.icon);
    for (const perk of tree.perks ?? []) icons.add(perk[3]);
  }
  await writeFile(`${DATA_DIR}/_legacy.json`, JSON.stringify(legacy));
  console.log("Legacy perks: saved");
}

// Try the fan sites first, then Wowhead's icon library for anything they don't have
async function fetchIcon(icon) {
  const sources = [
    `${BASE}/assets/icons/${icon}.jpg`,
    `${FAN_SITE}/assets/icons/${icon}.jpg`,
    `${FALLBACK}/${icon}.jpg`,
  ];
  for (const url of sources) {
    try {
      const res = await fetch(url);
      if (res.ok) return Buffer.from(await res.arrayBuffer());
    } catch {
      // try the next source
    }
  }
  return null;
}

let downloaded = 0;
let missing = 0;

for (const icon of icons) {
  const file = `${ICON_DIR}/${icon}.jpg`;

  try {
    await access(file);
    continue; // already have it
  } catch {
    // not downloaded yet
  }

  const buffer = await fetchIcon(icon);
  if (buffer) {
    await writeFile(file, buffer);
    downloaded++;
  } else {
    missing++;
  }

  await new Promise((resolve) => setTimeout(resolve, 50));
}

console.log(`Icons: ${downloaded} downloaded, ${missing} missing (missing ones show initials instead).`);