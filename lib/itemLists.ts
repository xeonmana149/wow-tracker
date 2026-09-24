"use client";

// Shared client-side helpers for the two per-character item lists: the
// general Wishlist (character_wishlist - already existed, just never had an
// item_id to link back to the shared item database) and the new Pre-BiS
// list (character_prebis - brand new). Both the Items page (ItemSearch.tsx)
// and the character page's gear tooltip (GearCard.tsx) call these same two
// functions, so "add to wishlist"/"add to Pre-BiS" behaves identically no
// matter where you clicked it from - see sql/items-migration-12.sql for the
// schema these read/write.
//
// Only ever called for a character in the CURRENT user's own roster (both
// callers already only offer characters from `characters` filtered to
// `user_id = auth.uid()`), so there's no separate ownership check here -
// same trust model the pre-existing WishlistCard.tsx form already uses.

import type { SupabaseClient } from "@supabase/supabase-js";

export type ListActionResult = { ok: true } | { ok: false; message: string };

export async function addToWishlist(
  supabase: SupabaseClient,
  args: { characterId: string; itemId: number; itemName: string }
): Promise<ListActionResult> {
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) return { ok: false, message: "You need to be logged in." };

  const { error } = await supabase.from("character_wishlist").insert({
    character_id: args.characterId,
    user_id: userData.user.id,
    item_id: args.itemId,
    item_name: args.itemName,
    priority: "Medium",
  });
  if (error) return { ok: false, message: error.message };
  return { ok: true };
}

export async function addToPreBis(
  supabase: SupabaseClient,
  args: { characterId: string; itemId: number; slot?: string | null }
): Promise<ListActionResult> {
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) return { ok: false, message: "You need to be logged in." };

  // onConflict ignores a second click on the same item for the same
  // character instead of erroring - see the unique(character_id, item_id)
  // constraint in the migration.
  const { error } = await supabase.from("character_prebis").upsert(
    {
      character_id: args.characterId,
      user_id: userData.user.id,
      item_id: args.itemId,
      slot: args.slot ?? null,
    },
    { onConflict: "character_id,item_id", ignoreDuplicates: true }
  );
  if (error) return { ok: false, message: error.message };
  return { ok: true };
}