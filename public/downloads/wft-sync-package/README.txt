WoW Forever Tracker - Background App
=====================================

What this is
-------------
This runs quietly in the background and keeps your character page on the
website up to date automatically - no terminal window, no copy/paste. It
lives as a small icon near your clock (the "system tray").

Setup (one time, about 2 minutes)
-----------------------------------
1. If you don't already have it, install Node.js: https://nodejs.org
   (click the button marked "LTS", run the installer, keep all the
   defaults).

2. In WoW, make sure you have the latest WoWForeverTracker addon
   installed (the one that auto-writes on logout), log into each
   character you want tracked, and log out (or /reload) once. No slash
   commands needed - it writes its data automatically every time you log
   out or reload from now on.

3. Double-click install.bat in this folder.
   - It installs a couple of small helper files it needs (one time only).
   - It'll ask if you want it to start automatically when you log into
     Windows - say yes if you want it to just always be running.
   - It then starts itself and opens a browser tab.

4. In that browser tab:
   - Fill in your website's address at the top.
   - Paste in your account sync token (from your account page on the
     website, "Account Auto-Sync Setup" panel - click "Generate token" if
     you don't have one yet). This is one token for your whole account,
     not one per character.
   - Below that, it lists every character on this PC that has used the
     WoWForeverTracker addon, each with a checkbox. Tick the ones you
     want tracked.

   Click "Save". You can close that browser tab now.

   This is how playing multiple characters works: any character you've
   ticked gets synced whenever it has fresh data - so switching from your
   Paladin to an Orc Mage just means the Mage's file is the one that gets
   picked up next. If it's a character the website hasn't seen before, it
   gets created there automatically the first time it syncs - no need to
   set anything up on the site first.

5. Look for a small icon near your clock (bottom-right of your screen on
   Windows - click the little up-arrow (^) if you don't see it right
   away). That's it running.

Removing a character
------------------------
If a character is gone for good (deleted in-game, or just something you
don't want tracked anymore), open Settings from the tray icon and click
"Remove from website" on that character's row. This deletes it from the
website completely (not just here) - it'll only come back if this PC
syncs it again, so leave it unticked (or delete its SavedVariables file)
if you don't want that to happen.

Using it day to day
---------------------
Nothing to do - it just runs. Right-click (or click, depending on your
Windows version) the tray icon for a small menu:
  - Sync now - force an immediate sync, useful for testing
  - Settings - reopens the setup page if you need to change anything
  - Open my character page - jumps straight to your page on the site
  - Quit - stops it (it'll start again next time you log in, if you said
    yes to that during setup)

You'll get a small notification popup each time it syncs, or if something
goes wrong.

Changing your settings later
-------------------------------
Click the tray icon and choose Settings, or delete config.json in this
folder and start it again.

Troubleshooting
-----------------
- Nothing appears in the tray after running install.bat: try double-
  clicking "Launch WoW Forever Tracker.vbs" directly in this folder.
- "npm install" fails in install.bat: you likely need to install (or
  reinstall) Node.js from https://nodejs.org first.
- Notification says sync failed with a website error: the site itself
  has a problem - let whoever runs it know.
- Notification says it can't find your WoW data file: click the tray
  icon, choose Settings, and re-pick the right character.
- Notification says "Unknown sync token" or similar: your account token
  is wrong or was regenerated on the site since - open Settings, get the
  current one from the site, and paste it in again.
- Getting repeated "Settings saved" notifications, or seeing more than
  one tray icon: you likely have more than one copy running. Only one is
  meant to run at a time now (later versions block this automatically) -
  quit it from the tray, and if it still seems stuck, restart your
  computer once to clear it out.
- "Remove from website" says it failed: check the site address and
  account token at the top of the page are still correct, then try again.
