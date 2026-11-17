# Forever Gold

A standalone gold-making addon for WoW Forever (interface 16001). It reads the
auction house and tells you, in plain English, what to craft, farm, sell and
flip with your own characters. It needs no other addon. It never buys, bids or
cancels anything, and it only posts an auction when you press Post on the Sell
panel.

Open it with `/gold`, the coin button on the minimap, or the "Advice" button
above the auction window.

## First run

1. Log in and talk to an auctioneer. Prices are read automatically (watch the
   counter above the auction window).
2. Open each profession window once so your recipes are learned.
3. Type `/gold`.

## Tabs

The window answers one question first: what should I do right now?

| Tab | What it answers |
| --- | --- |
| To do | Opens first. Undercut auctions to relist, then every quick win numbered best first, each with the gold it's worth: post these from your bags, buy these and vendor them, craft this, buy this from a vendor and resell it. Click a row to go to it. Below: the best farm if you've got an hour, and your characters (hover for each one). |
| Sell | What in your bags to auction (each row has a Sell button, see below), what to vendor, and which of your auctions were undercut. |
| Buy | Auction items cheaper than a vendor pays (no risk), vendor items that really resell at auction (proven by sale data, or limited vendor stock), and items far below their usual price. |
| Make | Three views, switched at the top. Craft: every recipe you know, with cost, sale price and profit after the 5% cut. Farm: gathering and grinding spots for your level and professions, your saved trips, and the Kills & Loot window. Routes: every ore vein, herb and fishing spot you've gathered; build a loop through a zone and follow the arrow. |

The Settings button at the top right holds the settings, the sale-rate status,
ideas for your professions with live prices, and a glossary.

## Kills & Loot window

The kill and loot tracker has its own small window, apart from the main one.
Open it with `/gold kills`, a right-click on the minimap button, or the button
under Make > Farm; starting the tracker opens it too. Drag it by its top bar,
stretch it taller from the bottom-right corner, or fold it down to one line
with "-". It remembers where you left it and whether it was open.

The top line shows the time, what you've made and gold per hour, with a green
dot while it's running. Below that: Start/Pause, Reset, Save trip (keeps a
record under Make > Farm) and three tabs.

- **Kills** - this trip's kills, your kill streak (and best; dying ends it),
  and every mob you've killed: how many, where, and what each kill was worth.
  Click a mob for its coin, drops, how often it drops green or better, kills
  since your last green, and your all-time numbers for it. Sort by most
  recent, most kills or most gold. Gathering is listed node by node
  ("Copper Vein x12").
- **Loot** - everything looted, most valuable first, at today's prices.
- **Money** - real money in and out: coin, auction sales from the mailbox,
  vendor sales, quests, and what you spent.

Kills are counted without the combat log: a mob you or your group tagged
dying in front of you, or a corpse you loot.

## The Sell button

At an auctioneer, press Sell on a Bags row. The addon checks that item's price
right then, shows the price it picked and why, and waits for you to press Post.

- It lists one copper under the cheapest sensible listing.
- It never goes below your floor: what the item costs to make, or what a vendor
  pays, plus 5% and the auction cut. Under the floor it says "not worth selling
  today" and won't post.
- It ignores a tiny quantity listed far below everything else.
- It never undercuts your own or your alts' auctions.
- The default quantity is one stack (or one item) so you don't flood the market.

Posting some other way (the auction house's own Sell screen, Auctionator)? A red
warning appears under the auction window while your price nets less than a
vendor pays, and any listing of yours under vendor price is called out once in
chat. Nothing is blocked.

## Sale rates

The game never tells an addon what sold. The WoW Forever Tracker website
compares Blizzard's hourly auction snapshots auction by auction (gone early =
bought, ran out = expired, identical cheaper repost = cancelled) and the tray app
writes the result into `MarketData.lua` every 20 minutes. After a `/reload` you
get "sells fast / steadily / slowly / rarely sells", sales per day and what items
actually sold for, in tooltips and on the Make, Sell and Buy tabs. Crafts are
ranked by profit you can actually expect, not profit on paper. Without the app
everything works as before. `/gold market` shows where the data stands.

Treat the numbers as estimates: a seller who cancels without reposting looks like
a sale. They're best for comparing items with each other.

## Tooltips

Blizzard's "Sell Price" line is replaced by a Vendor line (each, plus the
stack's total when you hover a stack). Under it: auction price, how many are
listed, when it was last scanned and by which character. If another of your characters (other realm or faction) has a price
for it, that shows too, with who scanned it and when.

How long ago is coloured so you can see at a glance how stale a price is:
green under 30 minutes, yellow under 6 hours, red after that.

Crafting materials also get a "Used in N recipes" line with the professions
(for example "Engineering 6, Blacksmithing 3"), and which of your characters
know any of them. Hold Shift for the recipes themselves; the ones a character
of yours knows are green with their name. The recipe list (`RecipeData.lua`)
covers every Forever recipe and is rebuilt from Blizzard's data by
`scripts/build-forever-recipes.mjs` in the site repo.

## On the website

The site's Auction House page (Search, Deals, Movers, Best sellers, Crafting
profits, Shopping list) works from Blizzard's hourly snapshots and needs
nothing from the addon. Its "My auctions & gold" tab does: `Web.lua` keeps a
small `webExport` table in the saved variables (each character's gold, the
auctions it saw when you last opened the auction house, and your saved farming
trips), and the tray app sends it to your account after you log out or
/reload. Only you can see it. The site then checks each auction against the
latest snapshot and tells you which have been undercut.

## Commands

- `/gold` - open or close the window
- `/gold scan` - read prices now (auction window must be open)
- `/gold scan fast` - force the one-download fast scan (the game allows it every 15 minutes)
- `/gold scan slow` - force the page-by-page scan
- `/gold kills` - show or hide the Kills & Loot window
- `/gold track` - start or pause the kill and loot tracker
- `/gold track reset` - wipe the tracker's numbers
- `/gold track save` - save the trip to Make > Farm and clear the tracker
- `/gold market` - where the sale-rate data stands
- `/gold stop` - stop following a route
- `/gold debug` - technical details if something looks wrong

## Files

- `Core.lua` - saved data, events, formatting, item lookups
- `Data.lua` - the built-in farming guide and tips (no prices; names with ID hints that are checked against the client)
- `Prices.lua` - the price book and vendor prices learned by visiting vendors
- `Market.lua` - sale rates from the tracker app's `MarketData.lua` (written by the app, not by hand)
- `Scan.lua` - auction house scanner
- `Chars.lua` - characters, professions, recipes, bags
- `Tracker.lua` - the kill and loot tracker
- `Advisor.lua` - the sums behind every recommendation
- `Route.lua` - node recording, route building, map drawing
- `Sell.lua` - the pricing rules and posting behind the Sell button, and the vendor-price guard
- `RecipeData.lua` - every Forever recipe and its reagents (generated, not edited by hand)
- `Recipes.lua` - what each item is used in, and which of your characters know those recipes
- `Web.lua` - the `webExport` table the tray app sends to the website
- `UI.lua` - the window, the on-screen route guide, minimap button, tooltips
- `TrackerUI.lua` - the Kills & Loot window

## Scanning

A scan uses the fast method (one download of every auction) whenever the game
allows it, which is once every 15 minutes. The download itself can take a while
on a busy auction house; the addon waits up to a minute for it, then reads it
in a few seconds. Pressing Scan while the game is still cooling down doesn't
fall back to the slow scan any more: it tells you how long until the next fast
scan and how old your prices are. `/gold scan slow` reads page by page if you
want fresh prices right now. The first fast scan on a realm is checked against
slow-scan prices before it is trusted. `/gold debug` shows how long the last
scan's download took to arrive.

A slow scan only sees each item's lowest price, which for gear can be a bid.
The Buy tab therefore only lists prices confirmed as buyouts: possible gear
deals are looked up one at a time after the scan and bid-only ones are dropped.

## Things to know

- The per-hour numbers under Make > Farm are rough guesses for ranking farms
  against each other. Use the session timer for real numbers.
- Routes start empty: the node map is built from your own gathering, so it
  also covers WoW Forever's new zones.
- Prices are filed per realm and faction, so Horde and Alliance characters
  keep separate price books.
