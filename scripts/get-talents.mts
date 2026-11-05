// Refreshes the bundled game data in lib/talent-data and the icons in
// public/talent-icons from talentsforever.com (current WoW Forever client
// data). The site fetches the same data live (re-checked daily, see
// lib/server-data.ts) and only falls back to these bundled files.
//
// HOW TO RUN IT:
//   npx tsx scripts/get-talents.mts
//
// Data: Talents Forever, CC BY 4.0. Icons and tooltip text belong to Blizzard Entertainment.
import { mkdir, writeFile, access } from "node:fs/promises";
import { fetchGameData, iconsIn, GAME_DATA_SOURCE } from "../lib/gameData";

const FAN_SITE = "https://wowforevertalent.com";
const FALLBACK = "https://wow.zamimg.com/images/wow/icons/large";
const DATA_DIR = "lib/talent-data";
const ICON_DIR = "public/talent-icons";

// Icons the site uses that aren't part of the downloaded data
const EXTRA_ICONS = [
  "race_human_male",
  "race_dwarf_male",
  "race_nightelf_male",
  "race_gnome_male",
  "race_orc_male",
  "race_scourge_male",
  "race_tauren_male",
  "race_troll_male",
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
  "inv_misc_questionmark",
];

async function fetchJson(url: string) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`status ${res.status}`);
  return res.json();
}

await mkdir(DATA_DIR, { recursive: true });
await mkdir(ICON_DIR, { recursive: true });

const { classes, racials, legacy, failed } = await fetchGameData(fetchJson);
for (const f of failed) console.error(`Could not download ${f}`);

for (const data of classes) {
  await writeFile(`${DATA_DIR}/${data.class.toLowerCase()}.json`, JSON.stringify(data));
  const count = data.trees.reduce((n, t) => n + t.talents.length, 0);
  console.log(`${data.class}: ${count} talents`);
}

await writeFile(`${DATA_DIR}/_racials.json`, JSON.stringify(racials));
console.log(`Racials: ${Object.keys(racials.races).length} races`);

// Kept for loadIcons() - race picture by race name, ability picture by ability name
const raceIcons: Record<string, string> = {};
const abilityIcons: Record<string, string> = {};
for (const [race, r] of Object.entries(racials.races)) {
  if (r.icon) raceIcons[race] = r.icon;
  for (const a of r.abilities) if (a.icon) abilityIcons[a.name] = a.icon;
}
await writeFile(`${DATA_DIR}/_icons.json`, JSON.stringify({ races: raceIcons, abilities: abilityIcons }));

if (legacy) {
  await writeFile(`${DATA_DIR}/_legacy.json`, JSON.stringify(legacy));
  console.log(`Legacy perks: ${legacy.trees.length} trees`);
}

const icons = iconsIn(classes, racials, legacy);
for (const icon of EXTRA_ICONS) icons.add(icon);
for (const data of classes) icons.add("class_" + data.class.toLowerCase());

// Try the fan sites first, then Wowhead's icon library for anything they don't have
async function fetchIcon(icon: string) {
  const sources = [
    `${GAME_DATA_SOURCE}/assets/icons/${icon}.jpg`,
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
const missing: string[] = [];
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
    missing.push(icon);
  }
  await new Promise((resolve) => setTimeout(resolve, 50));
}

console.log(`Icons: ${downloaded} downloaded, ${missing.length} missing${missing.length ? ": " + missing.join(", ") : ""}.`);
