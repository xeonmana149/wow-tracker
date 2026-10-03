"use client";

import { useState } from "react";
import Link from "next/link";
import { ShowcaseBadge } from "./AchievementShowcase";
import AccountBadgeTile from "./AccountBadgeTile";
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
  // Pin state for the favourite achievement card when it's an account badge
  // (2026-10-03, "can we make hover work on this") - AccountBadgeTile is a
  // controlled component (see AccountBadgesGrid.tsx), and there's only ever
  // one of these shown here, so a plain local boolean does the same job
  // AccountBadgesGrid's shared openKind does for a whole grid of them.
  const [achievementPinned, setAchievementPinned] = useState(false);

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
            uses - hover preview and click-through to the achievement already
            built in) or an account badge (reuses AccountBadgeTile, same tile
            the Account Badges grid uses further down the page, for the same
            hover-to-preview/click-to-pin treatment - 2026-10-03, "can we make
            hover work on this"). Always earned here, since the Edit Profile
            picker only offers already-earned badges to choose from. */}
        <div className="rounded border border-neutral-700 bg-neutral-900 p-3">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-amber-400/70">Favourite Achievement</p>
          {favoriteAchievement?.type === "character" ? (
            <div className="mt-1.5 flex justify-center">
              <ShowcaseBadge characterId={favoriteAchievement.characterId} item={favoriteAchievement.item} />
            </div>
          ) : favoriteAchievement?.type === "account" ? (
            (() => {
              const badge = ACCOUNT_ACHIEVEMENT_BADGES[favoriteAchievement.kind];
              const [name, ...rest] = badge.label.split(" - ");
              return (
                <div className="mt-1.5 flex justify-center">
                  <AccountBadgeTile
                    icon={accountBadgeIconSrc(favoriteAchievement.kind, iconOverrides)}
                    name={name}
                    description={rest.join(" - ")}
                    earned
                    pinned={achievementPinned}
                    onTogglePin={() => setAchievementPinned((p) => !p)}
                    onRequestClose={() => setAchievementPinned(false)}
                  />
                </div>
              );
            })()
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
//
// 2026-10-03 ("have the item actually linked to the item database so you can
// hover and get the tooltip or click it and it takes you to the item page")
// - the icon and name now link to /items?itemId=<id> (ItemSearch.tsx reads
// that param and opens the item's full details immediately, see its own
// comment), and the tooltip was moved OUT of the icon's own h-12 w-12 box:
// it used to be nested inside that box, which also has overflow-hidden, so
// the tooltip's bottom-full positioning (which pushes it above the box) was
// being clipped away by its own parent - hover looked like it did nothing at
// all, when really the tooltip was rendering, just invisibly. It's a sibling
// now, same structure GearCard's own Tile uses.
function FavoriteItemCard({ favoriteItem }: { favoriteItem: NonNullable<AccountViewData["favoriteItem"]> }) {
  const [imgFailed, setImgFailed] = useState(false);
  const { entry, characterId, characterName } = favoriteItem;
  const color = entry.item_quality ? `#${entry.item_quality}` : "#ffffff";
  const itemHref = entry.item_id != null ? `/items?itemId=${entry.item_id}` : null;

  const icon = (
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
    </div>
  );

  return (
    <div className="group relative mt-1.5 flex items-center gap-2">
      {itemHref ? <Link href={itemHref}>{icon}</Link> : icon}
      <div>
        {itemHref ? (
          <Link href={itemHref} className="text-sm font-semibold hover:underline" style={{ color }}>
            {entry.item_name}
          </Link>
        ) : (
          <div className="text-sm font-semibold" style={{ color }}>
            {entry.item_name}
          </div>
        )}
        <p className="text-xs text-gray-400">
          <Link href={`/character/${characterId}`} className="hover:text-amber-300 hover:underline">
            {characterName}
          </Link>{" "}
          · {entry.slot}
        </p>
      </div>

      {/* Tooltip, same visual treatment as GearCard's ItemTooltip - a sibling
          of the icon/name now, not nested inside the icon's overflow-hidden
          box (see header comment above). */}
      <div className="invisible absolute bottom-full left-0 z-50 mb-2 w-max max-w-xs opacity-0 shadow-lg group-hover:visible group-hover:opacity-100">
        <div
          style={{ background: "linear-gradient(180deg, #0c0c14, #000005)", border: "1px solid #c8aa6e" }}
          className="rounded-md p-3 text-left text-sm"
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
  );
}