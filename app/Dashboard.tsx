"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { supabase } from "../lib/supabase";
import { LEGACY_CAP } from "../lib/legacy";
import { PROFESSION_ICONS, classIcon } from "../lib/icons";
import { SUPPLIED_BY } from "../lib/professions";
import { missingProfessions, whatsNext, type Todo } from "../lib/progress";
import CharacterCard, { type CardCharacter, type MilestoneKind } from "./CharacterCard";
import GameIcon from "./GameIcon";
import NextList from "./NextList";
import { MoneyDisplay } from "./MoneyIcons";
import AccountSyncSetup from "./AccountSyncSetup";


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
          "*, character_professions(profession, skill), character_talents(slot, tree, rank), character_legacy(rank)"
        )
        .eq("user_id", userData.user.id)
        .order("level", { ascending: false });

      if (error) {
        setError(error.message);
      } else {
        // Milestones are account-wide "firsts" (only 3 rows max, one per
        // kind), so it's cheap to just grab all of them and match them up
        // to whichever of your characters holds each one.
        const { data: milestoneRows } = await supabase
          .from("milestones")
          .select("kind, character_id");
        const milestonesByCharacter = new Map<string, MilestoneKind[]>();
        for (const m of (milestoneRows ?? []) as { kind: MilestoneKind; character_id: string }[]) {
          const list = milestonesByCharacter.get(m.character_id) ?? [];
          list.push(m.kind);
          milestonesByCharacter.set(m.character_id, list);
        }

        const withMilestones = (data ?? []).map((c) => ({
          ...c,
          milestones: milestonesByCharacter.get(c.id) ?? [],
        }));
        setCharacters(withMilestones as CardCharacter[]);
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

    // Legacy points live on the profile, not on a character, so this event
    // has no character_id - just a message and whoever gained the point.
    // Best-effort only, same as the sync-route events: never blocks saving.
    if (points > legacy) {
      try {
        await supabase.from("activity_events").insert({
          user_id: userId,
          kind: "legacy_point",
          message: `Reached ${points} Legacy point${points === 1 ? "" : "s"}`,
        });
      } catch {
        // ignored on purpose
      }
    }

    setLegacy(points);
    setLegacyMessage("");
    setEditingLegacy(false);
  }

  if (status === "loading") {
    return <main className="mx-auto max-w-[1500px] p-4 md:p-6">Loading...</main>;
  }

  if (status === "loggedOut") {
    return (
      <main className="mx-auto max-w-[1500px] p-4 md:p-6">
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
  const totalCopper = characters.reduce((sum, c) => sum + (c.money_copper ?? 0), 0);

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

  // What's next: account-wide, then character by character
  const missing = missingProfessions(characters);
  const accountTodos: Todo[] = [];
  if (missing.length > 0) {
    const names = missing.slice(0, 4).join(", ");
    const more = missing.length > 4 ? ` and ${missing.length - 4} more` : "";
    accountTodos.push({ kind: "profession", text: `No ${names}${more} on your account` });
  }
  const perCharacter = characters.map((c) => ({ c, todos: whatsNext(c, legacy) }));

  return (
    <main className="mx-auto max-w-[1500px] p-4 md:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-4xl font-bold">My Characters</h1>
        <Link href="/download" className="rounded bg-blue-600 px-4 py-2 text-white">
          Downloads
        </Link>
      </div>

       <AccountSyncSetup />

      <section className="mt-6 rounded-lg border border-neutral-700 bg-neutral-900/40 p-4">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
          Account statistics
        </h2>

        <div className="mt-3 flex flex-wrap gap-4">
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
          <div className="text-2xl font-bold"><MoneyDisplay copper={totalCopper} /></div>
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
      </section>

      {error && <p className="mt-4 text-red-400">{error}</p>}

      <div className="mt-6 grid gap-4 xl:grid-cols-3">
        <section className="rounded-lg border border-neutral-700 bg-neutral-900/40 p-4 xl:col-span-2">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
            Character list
          </h2>

          {characters.length === 0 && !error && (
            <p className="mt-3 text-gray-400">You have no characters yet.</p>
          )}

          <div className="mt-3 grid gap-4 sm:grid-cols-2">
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
        </section>

        <div className="flex flex-col gap-4">
          <section className="rounded bg-neutral-800 p-4">
            <h2 className="text-xl font-bold">What&apos;s next</h2>
            <p className="mt-1 text-xs text-gray-500">
              Worked out from your Pre-BiS lists, talents, Legacy and professions.
            </p>

            {accountTodos.length > 0 && (
              <div className="mt-3">
                <h3 className="text-sm">Account</h3>
                <div className="mt-1.5">
                  <NextList todos={accountTodos} />
                </div>
              </div>
            )}

            {characters.length === 0 ? (
              <p className="mt-3 text-sm text-gray-500">Create a character to get started.</p>
            ) : (
              <div className="mt-4 flex flex-col gap-4">
                {perCharacter.map(({ c, todos }) => (
                  <div key={c.id}>
                    <Link href={`/character/${c.id}`} className="flex items-center gap-2">
                      <GameIcon name={classIcon(c.class)} label={c.class} size={26} round />
                      <span className="font-bold text-white">{c.name}</span>
                      <span className="text-xs text-gray-500">Level {c.level}</span>
                    </Link>
                    <div className="mt-1.5 pl-9">
                      <NextList todos={todos} limit={4} empty="All caught up." />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>

          <section>
            <h2 className="text-xl font-bold">Profession Coverage</h2>
            <p className="mt-1 text-sm text-gray-400">
              ✓ covered · ✗ missing · ⚠ covered, but nobody gathers the materials
            </p>

            <ul className="mt-3 flex flex-col gap-2">
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
          </section>
        </div>
      </div>
    </main>
  );
}