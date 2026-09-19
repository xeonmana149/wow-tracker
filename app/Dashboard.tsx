"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { supabase } from "../lib/supabase";
import { LEGACY_CAP } from "../lib/legacy";
import { PROFESSION_ICONS } from "../lib/icons";
import AuthStatus from "./AuthStatus";
import CharacterCard, { type CardCharacter } from "./CharacterCard";
import GameIcon from "./GameIcon";

const PRIMARY = [
  "Alchemy",
  "Blacksmithing",
  "Enchanting",
  "Engineering",
  "Herbalism",
  "Leatherworking",
  "Mining",
  "Skinning",
  "Tailoring",
];

// Which gathering profession supplies each crafting profession
const SUPPLIED_BY: Record<string, string> = {
  Alchemy: "Herbalism",
  Blacksmithing: "Mining",
  Engineering: "Mining",
  Leatherworking: "Skinning",
};

export default function Dashboard({
  specIcons,
  treeNames,
}: {
  specIcons: Record<string, string>;
  treeNames: Record<string, string[]>;
}) {
  const [status, setStatus] = useState<"loading" | "loggedOut" | "ready">("loading");
  const [characters, setCharacters] = useState<CardCharacter[]>([]);
  const [error, setError] = useState("");
  const [userId, setUserId] = useState("");
  const [legacy, setLegacy] = useState(0);
  const [editingLegacy, setEditingLegacy] = useState(false);
  const [legacyDraft, setLegacyDraft] = useState("0");
  const [legacyMessage, setLegacyMessage] = useState("");

  useEffect(() => {
    async function load() {
      const { data: userData } = await supabase.auth.getUser();

      if (!userData.user) {
        setStatus("loggedOut");
        return;
      }
      setUserId(userData.user.id);

      const { data, error } = await supabase
        .from("characters")
        .select(
          "*, character_professions(profession, skill), character_talents(slot, tree, rank)"
        )
        .eq("user_id", userData.user.id)
        .order("level", { ascending: false });

      if (error) {
        setError(error.message);
      } else {
        setCharacters((data ?? []) as CardCharacter[]);
      }

      const { data: profile } = await supabase
        .from("profiles")
        .select("legacy_points")
        .eq("id", userData.user.id)
        .single();
      setLegacy(Math.min(LEGACY_CAP, profile?.legacy_points ?? 0));

      setStatus("ready");
    }

    load();
  }, []);

  async function saveLegacy() {
    const points = Math.min(LEGACY_CAP, Math.max(0, Math.round(Number(legacyDraft) || 0)));
    const { error } = await supabase
      .from("profiles")
      .update({ legacy_points: points })
      .eq("id", userId);

    if (error) {
      setLegacyMessage(error.message);
      return;
    }
    setLegacy(points);
    setLegacyMessage("");
    setEditingLegacy(false);
  }

  if (status === "loading") {
    return <main className="p-8">Loading...</main>;
  }

  if (status === "loggedOut") {
    return (
      <main className="mx-auto max-w-5xl p-4 md:p-8">
        <AuthStatus />
        <h1 className="text-4xl font-bold">WoW Forever Tracker</h1>
        <p className="mt-4">Track your characters, gear and talents with your friends.</p>
        <Link
          href="/login"
          className="mt-6 inline-block rounded bg-blue-600 px-4 py-2 text-white"
        >
          Log in / Sign up
        </Link>
      </main>
    );
  }

  const highestLevel = characters.length
    ? Math.max(...characters.map((c) => c.level))
    : 0;
  const totalGold = characters.reduce((sum, c) => sum + (c.gold ?? 0), 0);

  // Best skill for each profession across every character on the account
  const best: Record<string, { skill: number; character: string }> = {};
  for (const c of characters) {
    for (const p of c.character_professions ?? []) {
      if (!best[p.profession] || p.skill > best[p.profession].skill) {
        best[p.profession] = { skill: p.skill, character: c.name };
      }
    }
  }

  const coveredCount = PRIMARY.filter((p) => best[p]).length;

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-8">
      <AuthStatus />
      <h1 className="text-4xl font-bold">My Characters</h1>

      <div className="mt-6 flex flex-wrap gap-4">
        <div className="min-w-[8.5rem] flex-1 rounded bg-neutral-800 p-4">
          <div className="text-2xl font-bold">{characters.length}</div>
          <div className="text-sm text-gray-400">Characters</div>
        </div>
        <div className="min-w-[8.5rem] flex-1 rounded bg-neutral-800 p-4">
          <div className="text-2xl font-bold">{highestLevel}</div>
          <div className="text-sm text-gray-400">Highest level</div>
        </div>
        <div className="min-w-[8.5rem] flex-1 rounded bg-neutral-800 p-4">
          <div className="text-2xl font-bold">
            {coveredCount}/{PRIMARY.length}
          </div>
          <div className="text-sm text-gray-400">Professions</div>
        </div>
        <div className="min-w-[8.5rem] flex-1 rounded bg-neutral-800 p-4">
          <div className="text-2xl font-bold">{totalGold.toLocaleString()}g</div>
          <div className="text-sm text-gray-400">Total gold</div>
        </div>
        <div className="min-w-[8.5rem] flex-1 rounded bg-neutral-800 p-4">
          {editingLegacy ? (
            <div className="flex flex-col gap-2">
              <div className="flex items-center gap-2">
                <input
                  type="number"
                  min={0}
                  max={LEGACY_CAP}
                  value={legacyDraft}
                  onChange={(e) => setLegacyDraft(e.target.value)}
                  aria-label="Legacy points"
                  className="w-16 rounded bg-white p-1 text-black"
                />
                <span className="text-sm text-gray-400">/ {LEGACY_CAP}</span>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={saveLegacy}
                  className="rounded bg-blue-600 px-3 py-1 text-sm text-white"
                >
                  Save
                </button>
                <button
                  onClick={() => {
                    setEditingLegacy(false);
                    setLegacyMessage("");
                  }}
                  className="rounded bg-neutral-700 px-3 py-1 text-sm text-white"
                >
                  Cancel
                </button>
              </div>
              {legacyMessage && <p className="text-xs text-red-400">{legacyMessage}</p>}
            </div>
          ) : (
            <>
              <div className="text-2xl font-bold">
                {legacy}/{LEGACY_CAP}
              </div>
              <div className="text-sm text-gray-400">
                Legacy points{" "}
                <button
                  onClick={() => {
                    setLegacyDraft(String(legacy));
                    setEditingLegacy(true);
                  }}
                  className="text-blue-400 underline"
                >
                  edit
                </button>
              </div>
            </>
          )}
        </div>
      </div>

      {error && <p className="mt-4 text-red-400">{error}</p>}

      {characters.length === 0 && !error && (
        <p className="mt-6 text-gray-400">You have no characters yet.</p>
      )}

      <div className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {characters.map((c) => (
          <CharacterCard
            key={c.id}
            c={c}
            treeNames={treeNames[c.class]}
            specIcons={specIcons}
          />
        ))}
      </div>

      <Link
        href="/create"
        className="mt-6 inline-block rounded bg-blue-600 px-4 py-2 text-white"
      >
        Create Character
      </Link>

      <h2 className="mt-10 text-2xl font-bold">Profession Coverage</h2>
      <p className="mt-1 text-sm text-gray-400">
        ✓ covered · ✗ missing · ⚠ covered, but nobody on your account gathers the materials
      </p>

      <ul className="mt-4 grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
        {PRIMARY.map((profession) => {
          const found = best[profession];
          const supplier = SUPPLIED_BY[profession];
          const unsupplied = found && supplier && !best[supplier];

          return (
            <li
              key={profession}
              className="flex items-center justify-between gap-3 rounded bg-neutral-800 p-3"
            >
              <span className="flex items-center gap-2">
                <GameIcon
                  name={PROFESSION_ICONS[profession]}
                  label={profession}
                  size={28}
                />
                <span>
                  <span
                    className={
                      !found
                        ? "text-red-400"
                        : unsupplied
                        ? "text-yellow-400"
                        : "text-green-400"
                    }
                  >
                    {!found ? "✗" : unsupplied ? "⚠" : "✓"}
                  </span>{" "}
                  {profession}
                  {unsupplied && (
                    <span className="block text-xs text-yellow-500">
                      No {supplier} on your account to supply it
                    </span>
                  )}
                </span>
              </span>
              <span className="text-sm text-gray-400">
                {found ? `${found.skill} · ${found.character}` : "Missing"}
              </span>
            </li>
          );
        })}
      </ul>
    </main>
  );
}