"use client";

import { useState } from "react";
import Link from "next/link";
import { ShowcaseBadge } from "./AchievementShowcase";
import { ACCOUNT_ACHIEVEMENT_BADGES, accountBadgeIconSrc } from "../lib/accountAchievements";
import type { BadgeIconOverrides } from "../lib/badgeIconOverrides";
import type { AccountViewData } from "../lib/accountView";

// Account page showcase (2026-10-03, "ON ACCOUNT PAGE HAVE A CHARACTER
// SHOWCASE SECTION, A FAVOURITE STATISTIC OF THEIRS, FAVOURITE ACHIEVEMENT
// WHETHER ITS A CHARACTER ACHIEVEMENT OR AN ACCOUNT ACHIEVEMENT, AND AN ITEM
// SHOWCASE") - four independent picks, each shown as its own small card.
// Rendered for every viewer (owner and visitors to /account/[userId] alike),
// same as every other section on this page - picking what to show here is
// an owner-only action, handled entirely in the Edit Profile panel
// (app/account/page.tsx), not here. A pick that's null (never set, or its
// target got deleted - see lib/accountView.ts's resolution comment) shows a
// muted placeholder rather than hiding the card, so the four-card layout
// stays stable instead of reflowing as picks get set one at a time.
//
// "use client" + its own file for the same reason AccountBadgesGrid/
// FamilyTileIcon are split out - AccountView.tsx is intentionally hook-free
// (see its own header comment), and the item card below needs state for its
// broken-image fallback.
export default function AccountShowcase({
  favoriteCharacter,
  favoriteStatistic,
  favoriteAchievement,
  favoriteItem,
  iconOverrides,
}: Pick<AccountViewData, "favoriteCharacter" | "favoriteStatistic" | "favoriteAchievement" | "favoriteItem"> & {
  iconOverrides: BadgeIconOverrides;
}) {
  return (
    <div className="rounded-md border border-neutral-700 bg-neutral-800 p-4">
      <h2 className="text-lg">Showcase</h2>
      <p className="mt-1 text-xs text-gray-500">Hand-picked by the account owner, from Edit Profile.</p>

      <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
        {/* Favourite character */}
        <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Favourite Character</p>
          {favoriteCharacter ? (
            <Link
              href={`/character/${favoriteCharacter.id}`}
              className="mt-1.5 block text-sm font-semibold text-white hover:text-amber-300"
            >
              {favoriteCharacter.name}
              <span className="block text-xs font-normal text-gray-400">
                Lv.{favoriteCharacter.level} {favoriteCharacter.race} {favoriteCharacter.class}
              </span>
            </Link>
          ) : (
            <p className="mt-1.5 text-sm text-gray-500">Not set yet.</p>
          )}
        </div>

        {/* Favourite statistic */}
        <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Favourite Statistic</p>
          {favoriteStatistic ? (
            <div className="mt-1.5">
              <div className="text-sm font-semibold text-white">
                {favoriteStatistic.name}: <span className="text-amber-300">{favoriteStatistic.value}</span>
              </div>
              <p className="text-xs text-gray-400">
                {favoriteStatistic.characterName} · {favoriteStatistic.category}
              </p>
            </div>
          ) : (
            <p className="mt-1.5 text-sm text-gray-500">Not set yet.</p>
          )}
        </div>

        {/* Favourite achievement - either a character achievement (reuses
            ShowcaseBadge, same tile the character page's own trophy cabinet
            uses) or an account badge (small static tile - no pin/breakdown
            interactivity here, that belongs to the Account Badges grid
            further down the page, not a one-off showcase pick). */}
        <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Favourite Achievement</p>
          {favoriteAchievement?.type === "character" ? (
            <div className="mt-1.5 flex justify-center">
              <ShowcaseBadge characterId={favoriteAchievement.characterId} item={favoriteAchievement.item} />
            </div>
          ) : favoriteAchievement?.type === "account" ? (
            <div className="mt-1.5 flex items-center gap-2">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={accountBadgeIconSrc(favoriteAchievement.kind, iconOverrides)}
                alt=""
                className="h-10 w-10 rounded-sm border border-amber-900/70"
              />
              <span className="text-sm font-semibold text-white">
                {ACCOUNT_ACHIEVEMENT_BADGES[favoriteAchievement.kind].label}
              </span>
            </div>
          ) : (
            <p className="mt-1.5 text-sm text-gray-500">Not set yet.</p>
          )}
        </div>

        {/* Item showcase */}
        <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Item Showcase</p>
          {favoriteItem ? <FavoriteItemCard favoriteItem={favoriteItem} /> : <p className="mt-1.5 text-sm text-gray-500">Not set yet.</p>}
        </div>
      </div>
    </div>
  );
}

// Minimal version of GearCard's item tile - just the icon + name + tooltip
// on hover, no slot glyph/paperdoll context, since there's only ever one
// item here, not a full loadout.
function FavoriteItemCard({ favoriteItem }: { favoriteItem: NonNullable<AccountViewData["favoriteItem"]> }) {
  const [imgFailed, setImgFailed] = useState(false);
  const { entry, characterName } = favoriteItem;
  const color = entry.item_quality ? `#${entry.item_quality}` : "#ffffff";

  return (
    <div className="group relative mt-1.5 flex items-center gap-2">
      <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded border" style={{ borderColor: color }}>
        {entry.item_icon && !imgFailed ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={entry.item_icon}
            alt=""
            draggable={false}
            className="h-full w-full object-cover"
            onError={() => setImgFailed(true)}
          />
        ) : (
          <span className="flex h-full w-full items-center justify-center text-[9px] text-gray-400">
            {entry.slot}
          </span>
        )}

        {/* Tooltip, same visual treatment as GearCard's ItemTooltip */}
        <div className="invisible absolute bottom-full left-1/2 z-50 mb-2 w-max max-w-xs -translate-x-1/2 rounded-md p-3 text-left text-sm opacity-0 shadow-lg group-hover:visible group-hover:opacity-100">
          <div
            style={{ background: "linear-gradient(180deg, #0c0c14, #000005)", border: "1px solid #c8aa6e" }}
            className="rounded-md p-3"
          >
            <div className="font-semibold" style={{ color }}>
              {entry.item_name}
            </div>
            {(entry.tooltip ?? [])
              .filter((line) => line !== entry.item_name)
              .map((line, i) => (
                <div key={i} className="text-gray-300">
                  {line}
                </div>
              ))}
          </div>
        </div>
      </div>
      <div>
        <div className="text-sm font-semibold" style={{ color }}>
          {entry.item_name}
        </div>
        <p className="text-xs text-gray-400">
          {characterName} · {entry.slot}
        </p>
      </div>
    </div>
  );
}
