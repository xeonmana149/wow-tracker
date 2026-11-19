# Forever Gold

A standalone gold-making addon for WoW Forever (interface 16001). It reads the
auction house and tells you, in plain English, what to craft, farm, sell and
flip with your own characters. It needs no other addon. It never buys, posts or
cancels anything on its own: each of those happens only when you press the
button for it (the game needs a click for every one anyway).

Open it with `/gold`, the round infinity-coin button on the minimap, or the
"Advice" button in the auction window.

## Install

- **With the WoW Forever Tracker app:** open its Settings and press "Install
  Forever Gold". It goes into every AddOns folder the app knows, stays updated
  from then on, and the app writes the sale-rate data the addon uses.
- **By hand:** download
  [ForeverGoldAddon.zip](https://github.com/xeonmana149/wow-tracker/releases/latest/download/ForeverGoldAddon.zip)
  and unzip it into `World of Warcraft/_forever_/Interface/AddOns`, so you get
  `AddOns/ForeverGold/ForeverGold.toc`. Without the app there are no sale
  rates, and you update it yourself.

Restart the game after installing (not just /reload), then type `/gold`.

## First run

1. Log in and talk to an auctioneer. Prices are read automatically (watch the
   counter above the auction window).
2. Open each profession window once so your recipes are learned.
3. Type `/gold`.

## Tabs

The window answers one question first: what should I do right now?

| Tab | What it answers |
| --- | --- |
| To do | Opens first. Undercut auctions to relist, then every quick win numbered best first: post these from your bags, buy these and vendor them, craft this, buy this from a vendor and resell it. Each row is short (the item, then where it goes: "Vendor > auction house · The Barrens"); the full instructions are in the pane. Below: the best farm if you've got an hour, and a one-line account summary. |
| Sell | What in your bags to auction (each row has a Sell button, see below), what to vendor, and which of your auctions were undercut. |
| Buy | Auction items cheaper than a vendor pays (no risk), vendor items that really resell at auction (proven by sale data, or limited vendor stock), and items far below their usual price. |
| Make | Three views, switched at the top. Craft: every recipe you know, with cost, sale price and profit after the 5% cut. Farm: gathering and grinding spots for your level and professions, your saved trips, and the Farming Session window. Routes: pick a zone you've gathered in and the map (the zone's own map picture, with a pickaxe, leaf or hook on each recorded spot) previews a suggested loop. Tick Herbs, Ore or Fishing above the map; click a spot to leave it out, right-click to start there; then Start route and follow the arrow (Pause, Skip stop, End route). Save route remembers the ticks and start for that zone. Recorded spots aren't guaranteed to be up, and the lines are straight. A loot beam stands on the next stop (gold), the nearest recorded spot when no route runs (white), and an herb, vein or chest right in front of you that isn't recorded yet (blue). On the world map (OpenMap's too) the gathering button at the top right filters herbs, ore, fishing, chests and the route line; right-click it to hide them all. |
| Characters | A graph of your gold across all your characters over time (24 hours, 7 days, 30 days or all of it; hover for the exact amount at any point), and every character with class, level, gold and primary professions. Click one for all its professions. Gold is recorded from this version on. |

Each tab is a list on the left and a details pane on the right. Click a row
and the pane shows its sums (materials, listed price, the auction house's 5%
cut and, once, the profit), how well it sells, and a button that says exactly
what it does: Sell, Post all, Open auction search, View materials, View vendor
location (puts a map pin on the vendor, for vendors visited from this version
on).

Profit is labelled for what it is. "Potential profit" is based on what things
are listed at; without sale data the row says "demand unknown", and it's ranked
well below anything with proof that it sells, so an expensive listing alone
never tops the list. Every profit is before any deposit you lose on auctions
that don't sell. The window is only as tall as what's in it. Item quality shows
as the colour of the icon border.

The Settings button at the top right holds the settings, the sale-rate status,
ideas for your professions with live prices, and a glossary.

## Farming Session window

The kill and loot tracker has its own small window, apart from the main one.
Open it with `/gold kills`, a right-click on the minimap button, or the button
under Make > Farm; starting a session opens it too. Drag it by its top bar. It
remembers where you left it and whether it was open.

Its state shows at the top right: Idle, Recording (green dot) or Stopped
(yellow). Idle, it's just one "Start session" button. During a session it
shows time, kills, money actually earned (coin plus sales) and the estimated
value of the loot you're carrying, kept apart, with gold per hour beside the
buttons: Stop/Start (Start carries on from where you stopped), Save trip
(keeps a record under Make > Farm) and Reset.
"-" folds it into a narrow status strip (time, kills, gold per hour) for while
you farm. It grows downward as you kill and loot (up to a limit, then it
scrolls).

- **Kills** - this trip's kills, your kill streak (and best; dying ends it),
  and every mob you've killed: how many and what each kill was worth. Under
  each mob is a row of its drops, most common first, each with how often it
  dropped (35% = about one kill in three). Hover a drop for its share of all
  that mob's drops, your all-time rate and what it was worth. Click a mob for
  its coin, where you killed it, how often it drops green or better, kills
  since your last green, and your all-time numbers for it. Sort by most
  recent, most kills or most gold. Gathering is listed node by node
  ("Copper Vein x12").
- **Loot** - everything looted, most valuable first, at today's prices.
- **Money** - real money in and out: coin, auction sales from the mailbox,
  vendor sales and what you spent.

Quests aren't counted: quest items you loot and quest reward money stay out
of the totals, so the numbers show what farming is worth. Kills are counted
without the combat log: a mob you or your group tagged dying in front of you,
or a corpse you loot. Opening the same corpse twice counts its drops once.

## The auction window

Talking to an auctioneer opens Forever Gold's own auction window instead of the
game's. It has the game's three tabs, plus what the addon knows:

- **Browse** - search by name or pick a category (the game's own list). Each
  result shows the lowest price, the usual price, how it compares, and how fast
  it sells. **Deals** at the top of the categories lists the bargains from your
  last scan. Click a result for every listing, then buy:
  - stackable goods: type how many (or Max). The first click asks the auction
    house for the exact price; the second click, "Confirm: pay ...", buys.
    Cancel backs out. It buys cheapest first and skips your own listings.
  - gear: click the listing you want, then "Buy now".

  Each listing shows its **seller**. The box beside it says who has the most
  listed and who's cheapest, and when you look at an item again, sellers who
  cut their price (**cut**) or weren't there before (**new**) are marked
  (remembered for the session). Ctrl+click any gear to try it on.

  **Suspicious** marks prices that make no sense - mostly a gray item listed for
  far more than a vendor pays, which is gold being passed between accounts - and
  items whose usual price was built from listings like that. They're never
  called deals, and selling never undercuts them.
- **Sell** - a proposed listing for everything in your bags that can go on the
  auction house. The ones the advice recommends are ticked; tick or untick the
  rest (remembered). Press "Price check" once: every ticked item is looked up
  live and given a price (undercut, never under its floor) and a listing size.
  Then press **Post** once per listing - the button names the next one - until
  it says "All posted". The bar under the list sets the undercut (1 copper, 1%,
  5%), how much goes in each listing (a stack, 10, 5, 1, everything), how many
  listings per item, and how long they last. Click a row to see why it picked
  that price, type your own price ("1g 20s", "1.5g", or copper), or change the
  size with - and +. Skip passes on one. A price over 5 minutes old is checked
  again before it posts.
- **Auctions** - your auctions, each marked undercut, tied, cheapest, alone or
  sold. "Check prices now" looks each one up live (prices marked * are from
  your last scan). "Cancel next undercut" cancels them one click at a time, then
  you post them again from Sell once they're back from the mail. Click one to see
  what cancelling costs.

"Game's window" switches to the game's own auction window (remembered), with
the old strip above it; its "Forever Gold window" button switches back. The
game's window is still open underneath ours, just shrunk out of sight, so
Escape, walking away and the X all close the auction house as normal.

## The mailbox

Opening a mailbox opens Forever Gold's mailbox instead of the game's. The strip
under the tabs is on every tab: your **banker**, **Change banker**, and
**Quick-send to banker**.

- **Banker** - one of your characters on this realm and faction (the only ones
  you can mail). It's remembered per realm and faction, and starts as "Xeon
  Banker" if that character exists. Change banker also picks which material
  groups quick-send takes besides auction stock (none until you tick them).
- **Inbox** - your mail on the left, the one you pick on the right: sender,
  subject, expiry, letter, gold and attachments. Click an attachment to take it,
  "Take gold" for the gold, or "Collect all" / "Collect gold" for everything
  it's safe to take. Bulk collecting never pays C.O.D., never takes mail from a
  Game Master or a sale still pending, and never returns or deletes mail. C.O.D.
  mail can only be paid in the game's mailbox.
- **Send mail** has three modes:
  - **To banker** (what Quick-send opens): auction stock - what the Sell advice
    says to auction or you ticked on the auction window's Sell tab, not what you
    unticked - plus the groups you added. Materials a profitable recipe of yours
    uses stay, unless you ticked them to sell, and so does anything a rule sends
    to someone else.
  - **Apply rules**: what your rules send, grouped by recipient.
  - **Custom mail**: recipient, subject, letter, stacks, and gold or C.O.D.
  Every mail, stack, quantity and copper of postage is listed before anything
  goes. Click a row to leave it out of this send; right-click to always keep it.
  Mail takes whole stacks, so if the keep amount falls inside a stack the row
  says "whole stacks" and sends less. Gold is off until you tick "Include spare
  gold": it then sends what's above "Keep at least" after every mail's postage.
  "Keep at least" is nothing unless you set it (any amount in the Send tab, or
  steps from nothing to 100g in Settings); postage never takes you under it.
  Settings on the Tips tab also has a Mailbox section: which mailbox window to
  use, asking or auto-sending when a mailbox opens, and sending spare gold.
- **Auto-send rules** - each rule matches one item or a material group (cloth
  and bolts, herbs, ore and bars, leather and hides, elemental, enchanting, meat
  and fish, gems, or auction stock), sends it to a character or to "Banker"
  (whoever your banker is), and keeps an amount in your bags (counted across
  every stack). A rule can be account-wide or for one character. Rules run top
  to bottom and the first enabled one that matches owns the item. Anything
  addressed to the character you're on, soulbound, a quest item or locked
  stays. "Add suggested rules" adds cloth to Xeon Hexspark (keep 20), herbs to
  Xeon Raincaller (keep 5), ore and bars to Xeon Mana (keep 20), leather to Xeon
  Ironfang (keep 10) and auction stock to your banker, all switched off for you
  to check. "Preview matching mail" shows the result on Send mail. "Ask when a
  mailbox opens" (on by default) shows what your rules would send as the mailbox
  opens, with Send now, Review first or Not now. "Auto-send on mailbox open"
  (off unless you tick it) gets the first mail ready without asking.

The game only sends mail from a real button press, so each mail needs one
click of Send - even with auto-send. Forever Gold attaches the stacks, checks
them, and waits for your click; after the server confirms, the next mail gets
ready. Before every mail it reads your bags again (an item may have been used or
moved), re-checks the recipient, the keep amounts and your gold, and only ever
sends less than the preview, never more. One mail action runs at a time:
pressing twice, or collecting while sending, does nothing. If the server never
answers, nothing is sent again: it checks your bags and gold, says what most
likely happened and what to check, and stops. Closing the mailbox stops the
queue after whatever the server is working on.

"Game's mailbox" switches to the game's own mailbox (remembered; needed to pay
C.O.D.), with a "Forever Gold mailbox" button above it to switch back. It waits
if a mail is with the server.

## The Sell button

At an auctioneer, press Sell on a Bags row. The addon checks that item's price
right then, shows the price it picked and why, and waits for you to press Post.

- It lists just under the cheapest sensible listing: by 1 copper, 1% or 5%
  (Settings > Selling).
- It never goes below your floor: what the item costs to make, or what a vendor
  pays, plus 5% and the auction cut. Under the floor it says "not worth selling
  today" and won't post.
- It ignores a tiny quantity listed far below everything else.
- It never undercuts your own or your alts' auctions.
- The default quantity is one stack (or one item) so you don't flood the
  market. Settings > Selling can change it to everything you have, or one at
  a time, and set how long auctions last.

### Post all

With the auction house open and your prices read, press "Post all" on the
strip under the auction window (or at the top of the Sell tab). It goes
through everything the Sell tab says to auction, best first, one item at a
time: the panel shows the price it picked and you press "Post, then next".
With "one full stack" set it lists a stack, then the next stack of the same
item, before moving on. Anything under its floor, or with no price to go on,
is skipped by itself; press Skip to pass on one, or Stop to end it. The game
needs a click for every listing, so nothing is ever posted without you.

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
ranked by profit times how often they sell, not profit on paper: a craft that
makes a little and sells fast beats one that makes a lot and never sells.
Profitable crafts that hardly sell get their own section at the bottom of
Craft, and the Sell tab orders your bags the same way. Each row says how it
sells ("sells fast (~40/day, 85% sell)": sales a day across the region, and
the share of listings that sold rather than expired) and a verdict: "worth
listing", "list one or two" or "hardly sells". Without the app
everything works as before. `/gold market` shows where the data stands.

Treat the numbers as estimates: a seller who cancels without reposting looks like
a sale. They're best for comparing items with each other.

## Tooltips

Blizzard's "Sell Price" line is replaced by a Vendor line (each, plus the
stack's total when you hover a stack). Under it: auction price, how many are
listed, when it was last scanned and by which character. Then the margins: for
anything you can craft, what it costs to make and the profit with its margin
("+2s 74c  219% margin"), and for anything a vendor buys, how much more the
auction pays after the 5% cut ("+3s 49c  +698%"), or that the vendor pays more. If another of your characters (other realm or faction) has a price
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
- `/gold kills` - show or hide the Farming Session window
- `/gold track` - start or stop a farming session
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
- `Chars.lua` - characters, professions, recipes, bags, and gold over time
- `Tracker.lua` - the kill and loot tracker
- `Advisor.lua` - the sums behind every recommendation
- `Route.lua` - node recording, route building, map drawing
- `Sell.lua` - the pricing rules and posting behind the Sell button, and the vendor-price guard
- `Poster.lua` - the auction window's post queue, live price lookups, and your auctions' undercut checks and cancelling
- `RecipeData.lua` - every Forever recipe and its reagents (generated, not edited by hand)
- `Recipes.lua` - what each item is used in, and which of your characters know those recipes
- `Web.lua` - the `webExport` table the tray app sends to the website
- `UI.lua` - the window, the on-screen route guide, minimap button, tooltips
- `TrackerUI.lua` - the Farming Session window
- `AuctionUI.lua` - the auction window (Browse and buy, Sell, Auctions) that replaces the game's
- `Mail.lua` - the mailbox's banker, rules, send plans, and the one-at-a-time collect and send queue
- `MailUI.lua` - the mailbox window (Inbox, Send mail, Auto-send rules) that replaces the game's
- `Icon.tga` - the addon's icon (minimap button, window title, addon list)

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
