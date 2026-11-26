# Quality of life integration

Keep settings grouped by task rather than adding a separate panel for every
feature. Features that spend gold or act on quests must be individually
switchable; avoid automatic reward selection. Check for overlap with the
player's existing addons and do not enable duplicate automation by default.

## Loot and merchants

- Game auto-loot setting and opt-in faster auto-loot: implemented.
- Personal-gold automatic repair: implemented, opt-in.
- Automatic junk selling: opt-in; uses Forever Gold's junk and keep rules and
  rechecks each slot before selling, including during a queued sale.

## Quests

- Independently switchable acceptance and turn-in are opt-in. Hold Shift to
  pause; reward choices are left to the player. A single unambiguous gossip
  quest can be selected when verified non-repeatable and the NPC has no other
  dialogue options; other gossip is left to the player.
- Mark the highest vendor-value reward without choosing it automatically;
  waits for every choice's price before marking a winner.
- Completed quest XP: shows known rewards on the existing XP bar without
  covering rested XP. Unavailable reward data is excluded, not guessed.
- Quest nameplate indicators are opt-in; turn off overlapping Questie marks.
  Unknown and restricted objectives do not produce a mark.
- Quest-object glow uses the client's loot-effect setting. The gathering glow
  follows the single nearby soft-interaction target, not every node in range.

## Spells and camera

- The class training window lists bundled spells and includes a low-rank tab.
  An optional reminder checks after spell changes or a trainer visit. Clicking
  a suggestion picks up the higher rank outside combat for manual placement;
  right-click keeps an intentional downrank. Macros are never altered.
- The spellbook has a class training shortcut; browsing never buys spells.
- The optional maximum-camera-distance setting preserves the previous value.

The training guide covers class spells grouped by level, faction weapon and
pet trainers, pet trainer abilities, and expandable class quest milestones.
Quest prerequisites retain their one-of/all-of branches and locations link to
the encyclopedia map. Pet ability knowledge is only marked known when the
client confirms it. Beast Training observations are accumulated rather than
treating the active pet's abilities as hunter knowledge. Prices are recorded
by spell ID at a class trainer or imported from OneForAll's observed prices;
unknown prices are not guessed. Live-client verification remains pending.

Each feature should use the game's API rather than a parallel data cache where
possible, be tested independently, and be verified in the actual client before
claiming it replaces another addon.
