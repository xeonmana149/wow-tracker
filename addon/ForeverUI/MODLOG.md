# Forever UI continuation

## 2026-11-26 — Crafting cost box in the profession window (Claude)

- User: "say the cost of crafting something, like auction cost, put above
  estimated value". `Windows.lua` adds a "Crafting cost" box between the
  reagents and Estimated value: Per craft (all reagents for one Create),
  In your bags (value of reagents already held, from Forever Gold's
  `Char().bags`) and Still to buy. Prices are Forever Gold's cheapest source
  per reagent (`EvalRecipe().parts`, falling back to `AHPrice`/`VendorBuy`);
  hovering lists each reagent, its price and source. Missing prices show
  "+?". Estimated value's Cost stays (per item made).
- Placement: crafting cost first, the estimate only if both fit above the
  controls. Scenario test updated; both suites pass. Installed; previous
  copy in `output/forever-ui-backups/2026-11-26-craftcost/installed`.

## 2026-11-26 — Quest auto-accept takes every quest in a row (Claude)

- User: "make quest auto accept work from the dialogue menu with npc to
  accept all in a row automatically". It only acted when an NPC offered
  exactly one quest and no other gossip options, and ignored the classic
  QUEST_GREETING window, so multi-quest NPCs did nothing.
- `QualityOfLife.lua`: each GOSSIP_SHOW / QUEST_GREETING picks the next
  quest - finished turn-ins first (if turn-in is on), then available quests.
  The list reopens after each accept, so it chains. Quests beside other
  dialogue options are picked too; non-quest options never are. Still
  skipped: repeatable/daily, trivial (grey), unfinished turn-ins, Shift held.
  Unknown repeatability now counts as a normal quest. A quest picked in the
  last 15 s isn't re-picked (no loop on a full log). Greeting quests with no
  ID fall back to the title for that memory.
- `tests/quest_gossip.py` rewritten for the new rules (gossip + greeting);
  `tests/client.lua` knows QUEST_GREETING. Both suites pass. Option
  tooltips updated. Installed; previous copies in
  `output/forever-ui-backups/2026-11-26-quest-chain/installed`.
- Not checked in game: whether this client reopens the NPC list after an
  accept (if not, each talk to the NPC takes the next quest).

## 2026-11-26 — Edit Mode resizing, remembered windows, aligned header bars (Claude)

- Edit Mode / `/fui move` handles now resize: drag the gold corner grip or
  scroll over a handle (50–200%, saved in `ForeverUIDB.scale[key]`, applied
  before the position so the saved center holds). Right-click resets position
  and size. `ns.Place(frame, key, label, default, keep, opts)` gained `opts`:
  `noResize` (tooltip anchor, dispels), or `scaleOption`/`scaleMin`/`scaleMax`/
  `onScale` for elements with their own size setting (micro menu →
  `microScale`, healing frames → `healScale`).
- Hidden elements (no group, no tracked dungeon) still get a dimmer
  "(hidden)" handle; handles follow show/hide/resize while Edit Mode is open;
  elements built while it is open get one too.
- `ns.Adopt(frame, key, label, ext)` lets another addon's self-saving frame
  join Edit Mode. Forever Gold's `ForeverGoldTracker` exposes
  `frame.fuiExternal` (save/getScale/setScale/reset; `opts.trackerScale`).
- `ns.RememberWindow(frame, key)`: Encyclopedia, Instance Guide, settings and
  Trainer guide reopen where they were left (`windowPos`) at their saved size
  (`windowScale`, bottom-right grip). Forever Gold's main window, route guide
  and sell panel now save their positions too (`mainPos`, `guidePos`, `sellPos`).
- Top-of-screen bars share one header spec: 22 high, 16px controls 2 apart,
  3 in. Dungeon tracker: header 24→22, width 230→260, one-line 12pt title (it
  wrapped "Excavation Site: Wetlands" onto two lines), red close + gold-line
  fold. Damage meter scale 0.8→22/28 so its 28-high title row draws 22.
  Farming tracker fold uses the same drawn gold −/+.
- Damage meter: leaving Edit Mode now keeps a native Edit Mode move instead
  of snapping back to the addon's older saved spot.
- Tests: both suites pass. Installed changed ForeverUI files; previous
  installed copies in `output/forever-ui-backups/2026-11-26-editmode-pass/installed`.
- Not checked in game: the look of the aligned bars, grip feel, and the
  Forever Gold/WoWForeverTracker changes (those ship with a tray release).

## 2026-11-22 — Minimap calendar icon

- Existing Forever UI and mailbox icons are single 128×128 RGBA TGA textures,
  front-facing with soft transparent edges and warm gold artwork. The calendar
  uses the same format and a centered, compact silhouette.
- Mail is positioned to the left of the minimap; the calendar button sits
  below its right edge. The clock no longer opens the calendar.

## 2026-11-21 — Profession window interior

- The Camelot crafting page's `Profession-Background-Template2` parchment
  is hidden, allowing the shared dark panel to show through. Profession
  side tabs get the shared gold-edged panel while retaining their native
  icons, selected indicator, and interaction.
- Mock tests cover late addon loading, reopening, and preservation of recipe
  and tab art. The changed `Windows.lua` was installed with its previous
  version backed up under `output/forever-ui-backups/2026-11-21-professions`.
- This is one pass, not the completion of all remaining window interiors.
  Inspect the crafting page in game and continue the spellbook, talents,
  profession book, and other screen-specific art using client frame sources.

## 2026-11-21 — Codex continuation from Claude

User requested continuation of the full UI addon, prioritizing unfinished work
and fixes. Recovered Claude's latest handoff from its local project transcript:
shared window skins were implemented and installed; work then stopped while
diagnosing the missing Pawn upgrade arrow in Forever Gold's inventory.

### Existing implementation

- UI addon: `addon/ForeverUI`, interface 16001, version 0.1.0.
- Standard Lua addon API only; no client patching or injected code.
- Existing modules: action bars, XP/reputation, micro menu, bag bar, minimap,
  tooltips, cast bars, swing timers, auras, damage meter and shared window skins.
- `/fui` opens settings; `/fui move`, `/fui reset`, `/fui errors` are available.
- Inventory/mail/auction replacement remains in `addon/ForeverGold`.
- ForeverUI is intentionally excluded by local `.git/info/exclude`; leave it
  local until the user requests publication. No release/version bump performed.

### Fixes in this pass

- Installed Pawn 2.14.4 documents `PawnShouldItemLinkHaveUpgradeArrow(link,
  true)` in `PawnBags.lua`. The previously called container API does not exist
  in this installation. Its result is tri-state: nil means retry, including
  when Pawn has exhausted its quarter-second calculation budget.
- Forever Gold now uses that API, retries pending arrows after 0.3 seconds,
  skips stale/hidden buttons, honors both addons' switches, and observes
  `PawnResetBags` to refresh arrows after settings/equipment changes. The hook
  deliberately leaves Pawn's default bag integration registered for users who
  switch the Forever Gold bag replacement off during a session.
- The old Pawn test fabricated the missing API. Replaced it with the installed
  public contract and regression cases covering delayed results and settings.
- ForeverUI coalesces repeated protected-frame placement repairs during combat,
  reuses the recursion guard when replacing a placement, and logs deferred errors.
- Optional cast/buff frames no longer truncate iteration at a nil entry.
- Weapon enchants active at login get their bright border immediately.
- Close-button texture cleanup handles missing optional textures.
- Both test scenarios now raise on failure instead of merely printing FAILED
  while returning exit code zero.

### Verification and continuation

Tests run through the existing Lua 5.1 `lupa` environment used by Claude;
system Python does not have lupa installed. Test logs are in
`output/forever-gold-tests.log` and `output/forever-ui-tests.log`.
Final result: **852 Forever Gold checks and 79 Forever UI checks passed**.
`git diff --check` also passed (only the repository's existing line-ending
conversion warnings).

Installed and SHA-256 verified the five changed runtime files in
`C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns`:
`ForeverGold/BagUI.lua` and `ForeverUI/{Core,Combat,Auras,Windows}.lua`.
Original files and a hash manifest are saved under
`output/forever-ui-backups/2026-11-21-continuation/`.
No new runtime files were added; `/reload` loads these fixes for a running
client. No release, commit, upload or production website change was made.

These are offline client-mock tests, not proof of protected-frame behaviour or
appearance in the actual game. WoW was not running during initial discovery.
Next in-game checks: the reported ring's arrow, Pawn scale changes while bags
are open, no arrows for offline alts, pet casting, pre-existing weapon enchants,
move mode before/after combat, and the character/spellbook/profession windows.

The per-window art pass (character equipment slots/model backdrop, spellbook,
talents, professions) remains unfinished. Use the actual client frame sources
and screenshots rather than guessing child names or declaring the full UI done.

## 2026-11-21 — Edit Mode and character window first pass

- `EditMode.Enter` and `EditMode.Exit` now show/hide the addon's existing gold
  movement handles alongside native Edit Mode; native systems remain controlled
  by the game. Addon positions save immediately and are not included in the
  game's layout save/revert or per-layout profiles. `/fui move` still works.
- Existing equipment buttons gain transparent gold edge frames, leaving native
  item art, quality borders, tooltips, model and interaction intact.
- Offline ForeverUI and ForeverGold tests passed. Installed Mover.lua and
  Windows.lua with originals at `output/forever-ui-backups/2026-11-21-edit-mode`.
- Game was actively crafting; no live client interaction was performed. Check
  Edit Mode callbacks, movement, combat behaviour, equipment borders and native
  drag/drop in-game. Character-window visual redesign and remaining windows are
  still in progress.
