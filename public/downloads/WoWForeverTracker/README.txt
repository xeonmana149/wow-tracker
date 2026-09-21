WoW Forever Tracker - companion addon (v0.1.0)
================================================

WHAT THIS IS
------------
A small addon for the WoW Forever beta that reads your character's basic
info, stats, professions, equipped gear, and (experimentally) talent/Legacy
points, and shows them to you as a block of text (JSON) that you copy and
paste somewhere on the website. It does not send anything anywhere by
itself - it just saves you typing everything in by hand.

INSTALL
-------
1. Find your WoW Forever install folder, then go into:
   _classic_beta_\Interface\AddOns\
2. Copy the whole "WoWForeverTracker" folder (this folder) in there, so you
   end up with:
   _classic_beta_\Interface\AddOns\WoWForeverTracker\WoWForeverTracker.toc
   _classic_beta_\Interface\AddOns\WoWForeverTracker\WoWForeverTracker.lua
3. Start the game (or /reload if it's already running) and make sure the
   addon is ticked on at the character-select AddOns list.

USE
---
Log in to a character, then type in chat:

  /wft export
      Opens a window with all the data it could read, as one block of
      text (JSON). Click inside the box, press Ctrl+A then Ctrl+C to
      copy it, then paste it wherever the website asks for it.

  /wft probe
      Prints a list of game functions this addon uses and whether this
      client build actually has each one. Useful for me to debug things
      if a section of the export keeps coming back empty - if that
      happens, run this and send me what it prints.

  /wft traits
      Talents and Legacy points are experimental right now (see below).
      This prints how many "learned" trait nodes it could find, without
      opening the full export window.

  /wft scan
      Runs probe, traits and export all in one go.

WHAT'S SOLID VS. EXPERIMENTAL
------------------------------
Solid (should just work): name, race, class, faction, level, guild, gold,
primary stats, attack power, health/mana, move speed, armor, crit/dodge/
parry/block %, resistances, professions and their skill levels, and the
item links for whatever's equipped in each gear slot.

Experimental: talents and Legacy. The beta runs these through the same
"trait tree" system Retail WoW uses (C_Traits), but nobody has published
which tree/node IDs correspond to which actual talent or Legacy perk yet.
So for now the addon dumps the raw node IDs, tree IDs and rank counts it
can see rather than guessing names - it'll show a config with some number
of "learned nodes," not "Pursuit of Justice, rank 3." Once you've spent
some points, run /wft traits and send me what it prints (or the full
export) and I can start building the ID-to-talent-name mapping from real
data instead of guessing at it.

Not attempted at all: the hidden hit-chance-vs-boss numbers from the
weapon skill tooltip (same limitation discussed before - there's no single
game API for those pre-level-cap), and PvP rank/honor (no confirmed API
for those yet either). Keep typing those into the website by hand for now.

WHY THERE'S NO "AUTO-SYNC" YET
-------------------------------
Two things about this beta build rule that out for now:
  1. It never reloads SavedVariables on login, so an addon can't quietly
     remember anything between sessions - only what you gather in the
     current session exists.
  2. There's no way for an addon to make outbound web requests to your
     website's server. Addons can only talk to the WoW client itself.

So "paste this block of text into the website" is the realistic version of
this for as long as the beta has these restrictions. If either of those
changes later, this can be upgraded to something more automatic.

IF SOMETHING GOES WRONG
------------------------
If typing /wft does nothing, or you see a Lua error, run /wft probe and
send me the full output plus whatever error text appeared - that tells me
exactly which function names this client build uses instead of the ones
this version guesses at, which is normally all it takes to fix.
