import type { CardCharacter } from "../CharacterCard";

// Split out from the old standalone /crafting route so both the Items page
// (which fetches this server-side) and CraftingBrowser (which just renders
// it) can share the same shape without importing from a page.tsx module.
export type CraftingCharacter = Pick<CardCharacter, "id" | "name" | "class" | "character_professions">;
export type CraftingPlayer = { id: string; name: string; characters: CraftingCharacter[] };