"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { supabase } from "../lib/supabase";
import LegacyChallengesSection from "./LegacyChallengesSection";

// Thin standalone wrapper around LegacyChallengesSection (2026-09-27 - the
// actual browser UI moved there so it can also be embedded directly in
// CharacterAchievementsPage as a "Legacy Challenges" family, making the two
// achievement systems feel like one place instead of two separate pages).
// Kept around so /character/[id]/legacy still works for anyone who
// bookmarked or linked directly to it.
export default function CharacterLegacyPage({ characterId }: { characterId: string }) {
  const [characterName, setCharacterName] = useState("");

  useEffect(() => {
    supabase
      .from("characters")
      .select("name")
      .eq("id", characterId)
      .single()
      .then(({ data }) => setCharacterName(data?.name ?? ""));
  }, [characterId]);

  return (
    <main className="mx-auto max-w-6xl p-4 text-white md:p-6">
      <Link href={`/character/${characterId}/achievements`} className="text-xs text-gray-500 hover:underline">
        ← Back to {characterName || "character"}&apos;s achievements
      </Link>
      <h1 className="text-3xl font-bold">Legacy Challenges</h1>
      <LegacyChallengesSection characterId={characterId} />
    </main>
  );
}