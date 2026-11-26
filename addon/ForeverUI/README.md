# Forever UI

A local WoW Forever UI addon (interface 16001) using the dark panels and thin
gold borders of Forever Gold. It styles the game's existing action buttons and
windows so their original controls and bindings remain available.

## Included

- Action bars, cast bars, swing timers and buff/debuff icons.
- XP and watched reputation bars.
- Micro menu and bag buttons.
- Square minimap, addon-button drawer, mail, coordinates, clock, FPS and latency.
- Movable default tooltip position.
- Built-in damage meter skin.
- Shared window borders, titles, close buttons, insets, tabs and common controls.

The compact inventory, bank, mailbox and auction features are in **Forever
Gold**, not this addon. Window-specific interiors are still being developed;
this is not a completed replacement for every game screen.

## Controls

- `/fui`: settings and module switches.
- `/fui instance`: open the separate Instance Guide for dungeon and raid bosses, quests and entrance locations.
- `/fui move`: drag the gold placement boxes; right-click one to reset it.
- `/fui reset`: reset saved positions.
- `/fui errors`: errors captured during this session.

Use the game's Edit Mode for its action bars, cast bars and other native layouts.
Module switches require `/reload`. A first installation or newly added files
may require a full restart of the client.

## Offline tests

With Python and `lupa` available, from the repository root:

```text
python addon/ForeverUI/tests/runtest.py
python addon/ForeverGold/tests/runtest.py addon/ForeverGold
```

The UI suite builds on Forever Gold's mock client. It checks behaviour, not the
actual rendered game UI or the client's protected-frame restrictions. Both
scenarios exit with an error if a check fails.

See `MODLOG.md` for the continuation notes and remaining in-game checks.
