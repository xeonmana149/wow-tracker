-- Forever Gold - the mailbox engine
--
-- Everything the mailbox window (MailUI.lua) does goes through here:
--   * who you can mail (your own characters on this realm and faction),
--     and which one is your banker
--   * auto-send rules: "cloth goes to my tailor, keep 20 of each"
--   * plans: exactly which stacks go to whom, in which mail, for how much
--     postage, before anything is sent
--   * one shared, paced queue for everything that talks to the server:
--     taking mail, taking gold, sending mail
--
-- How the queue stays safe (checked against Blizzard_MailFrame and the
-- generated MailInfo / SecureTransfer docs on the `forever` branch):
--   * One command at a time. Nothing new is sent while C_Mail.IsCommandPending()
--     says the server is still busy, and every command waits for its answer
--     (MAIL_SEND_SUCCESS / MAIL_FAILED for sends; the inbox actually changing
--     for takes) before the next one.
--   * Sending: the attachments are put on the mail first and checked, then the
--     player presses Send once per mail. SendMail is only ever called from that
--     click, so it works even if this client wants a real click for every mail.
--     Taking mail needs no click (the game's own "Open all" does it on a timer).
--   * No reply in time never means "send it again". The bags and gold are
--     checked to say what most likely happened, and the queue stops.
--   * Never: pay C.O.D., return mail, delete mail.

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local MB = {
    open = false,          -- a mailbox is open right now
    inbox = {},            -- the last read of the inbox (see readInbox)
    inboxState = "closed", -- closed | loading | ready
    numShown = 0, numTotal = 0,
    exclude = {},          -- item IDs left out of the current send preview
    status = { kind = "idle", text = "" },
    unclear = {},          -- shipments whose result never came back
}
ns.Mail = MB

MB.POSTAGE = 30        -- copper per attachment (30c for a letter with none)
MB.DEFAULT_BANKER = "Xeon Banker"
local PACE = 0.3       -- seconds between two commands (the game's own Open All uses 0.15)
local TAKE_TIMEOUT = 10
local SEND_TIMEOUT = 20
local CONFIRM_TIMEOUT = 120 -- while the game's own "are you sure?" dialog is up
local BUSY_LIMIT = 60       -- PACE ticks the server may stay busy before we give up

local function O()
    return ns.db.opts
end

local function D()
    local m = ns.db.mail
    if type(m) ~= "table" then
        m = {}
        ns.db.mail = m
    end
    if type(m.rules) ~= "table" then m.rules = {} end
    m.nextId = m.nextId or 1
    return m
end
MB.Data = D

function MB.MaxAttach()
    return tonumber(ATTACHMENTS_MAX_SEND) or 12
end

local function maxReceive()
    return tonumber(ATTACHMENTS_MAX_RECEIVE) or 16
end

local function plain(copper)
    return ns.StripCodes(ns.Money(copper or 0))
end
MB.Plain = plain

local function plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end
MB.Plural = plural

function MB.Reserve()
    return max(0, floor(tonumber(O().mailReserve) or 0))
end

-- Why a mail can't be paid for: under the gold you keep, or (with no
-- reserve set) more than you have.
local function shortWords()
    local r = MB.Reserve()
    if r > 0 then
        return "would take you under the " .. plain(r) .. " you keep"
    end
    return "is more gold than you have"
end

function MB.Postage(attachments)
    return MB.POSTAGE * max(1, attachments or 0)
end

local function setStatus(kind, text)
    MB.status = { kind = kind, text = text or "", at = GetTime() }
    ns.Fire("MAIL")
end
MB.SetStatus = setStatus

----------------------------------------------------------------------
-- Characters: who this character can mail
--
-- Same account (every record in this SavedVariables file is), same realm and
-- same faction. The character's realmKey is "<realm ID>-<faction>", the same
-- key the price book uses.
----------------------------------------------------------------------

local function sameName(a, b)
    return type(a) == "string" and type(b) == "string" and a:lower() == b:lower()
end

local function myName()
    return ns.Char().name or ns.try(UnitName, "player") or "?"
end

function MB.IsSelf(key, name)
    if key and key == ns.charKey then
        return true
    end
    return name ~= nil and sameName(name, myName())
end

-- Every character you can mail from here, by name. With `withSelf`, this
-- character too (marked self = true), for the banker picker.
function MB.Characters(withSelf)
    local out = {}
    for key, c in pairs(ns.db.chars or {}) do
        local isSelf = key == ns.charKey
        if c.name and c.realmKey and c.realmKey == ns.realmKey and c.faction == ns.player.faction
            and (withSelf or not isSelf) and (isSelf or not sameName(c.name, myName())) then
            out[#out + 1] = { key = key, name = c.name, class = c.class, level = c.level, faction = c.faction,
                money = c.money, self = isSelf or nil }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Is `key` one of your characters you can mail from here?
function MB.CanMail(key)
    local c = key and ns.db.chars[key]
    if not c or not c.name then
        return false, "unknown character"
    end
    if key == ns.charKey then
        return false, "self"
    end
    if c.realmKey ~= ns.realmKey or c.faction ~= ns.player.faction then
        return false, "another realm or faction"
    end
    return true
end

function MB.NameOf(key)
    local c = key and ns.db.chars[key]
    return c and c.name or nil
end

----------------------------------------------------------------------
-- The banker
----------------------------------------------------------------------

-- Your banker's character key on this realm, or nil. Your own choice if you
-- made one; otherwise "Xeon Banker" if that character exists here.
function MB.BankerKey()
    local saved = type(O().mailBanker) == "table" and O().mailBanker[ns.realmKey] or nil
    if saved then
        if saved == ns.charKey or MB.CanMail(saved) then
            return saved
        end
    end
    for _, c in ipairs(MB.Characters(true)) do
        if sameName(c.name, MB.DEFAULT_BANKER) then
            return c.key
        end
    end
    return nil
end

function MB.SetBanker(key)
    if type(O().mailBanker) ~= "table" then
        O().mailBanker = {}
    end
    if key ~= ns.charKey and not MB.CanMail(key) then
        return false
    end
    O().mailBanker[ns.realmKey] = key
    ns.Fire("MAIL")
    return true
end

----------------------------------------------------------------------
-- Material categories
--
-- Trade goods by the subclass the game files them under (the auction
-- house's own Trade Goods categories are built from the same subclasses).
----------------------------------------------------------------------

local function tg(sub)
    return function(it) return it.c == 7 and it.s == sub end
end

MB.CATS = {
    { key = "cloth", name = "Cloth & bolts", icon = 2589, test = tg(5) },
    { key = "herbs", name = "Herbs", icon = 2447, test = tg(9) },
    { key = "metal", name = "Ore & bars", icon = 2770, test = tg(7), tip = "Everything the game files under Metal & Stone: ore, bars and stone." },
    { key = "leather", name = "Leather & hides", icon = 2318, test = tg(6) },
    { key = "elemental", name = "Elemental", icon = 7067, test = tg(10) },
    { key = "enchanting", name = "Enchanting materials", icon = 10940, test = tg(12) },
    { key = "cooking", name = "Meat & fish", icon = 2672, test = tg(8) },
    { key = "gems", name = "Gems", icon = 818, test = function(it) return it.c == 3 end },
    { key = "scrolls", name = "Scrolls", icon = 954, test = function(it) return it.c == 0 and it.s == 4 end,
        tip = "Every scroll: stat scrolls (Strength, Intellect...) and the mage's Comprehension scrolls (Scroll: KWYJIBO...)." },
    { key = "stock", name = "Auction stock", icon = nil, stock = true,
        tip = "Only what you have ticked to sell on the auction window's Sell tab." },
}
MB.CAT = {}
for _, c in ipairs(MB.CATS) do
    MB.CAT[c.key] = c
end

local function postPick(id)
    local p = O().postPick
    return p and p[id]
end

function MB.InCategory(key, id)
    local cat = MB.CAT[key]
    if not cat then
        return false
    end
    if cat.stock then
        return postPick(id) == true
    end
    local it = ns.Item(id)
    if not it or not it.c then
        return false
    end
    return cat.test(it) and true or false
end

----------------------------------------------------------------------
-- Rules
--
-- rule = { id, on, cat = "cloth" | item = itemID, to = "banker" | charKey,
--          keep = how many to keep in bags (total, all stacks),
--          scope = "account" | charKey (this character only) }
-- The list's order is the priority: the first enabled rule that matches an
-- item owns all of it.
----------------------------------------------------------------------

function MB.Rules()
    return D().rules
end

function MB.RuleApplies(r)
    return r.on and (r.scope == nil or r.scope == "account" or r.scope == ns.charKey)
end

function MB.ActiveRules(list)
    local out = {}
    for _, r in ipairs(list or D().rules) do
        if MB.RuleApplies(r) then
            out[#out + 1] = r
        end
    end
    return out
end

function MB.RuleMatches(r, id)
    if r.item then
        return r.item == id
    end
    return r.cat ~= nil and MB.InCategory(r.cat, id)
end

function MB.RuleName(r)
    if r.item then
        return ns.ItemName(r.item)
    end
    local c = MB.CAT[r.cat or ""]
    return c and c.name or "Pick what to match"
end

-- Who a rule sends to here: key, name, problem ("self" | "nobanker" |
-- "elsewhere" | "unset").
function MB.RuleTarget(r)
    local key = r.to
    if key == "banker" then
        key = MB.BankerKey()
        if not key then
            return nil, nil, "nobanker"
        end
    end
    if not key then
        return nil, nil, "unset"
    end
    if key == ns.charKey then
        return key, myName(), "self"
    end
    local ok = MB.CanMail(key)
    if not ok then
        return key, MB.NameOf(key), "elsewhere"
    end
    return key, MB.NameOf(key)
end

function MB.NewRule(fields)
    local d = D()
    local r = { id = d.nextId, on = false, keep = 0, scope = "account", to = "banker" }
    d.nextId = d.nextId + 1
    for k, v in pairs(fields or {}) do
        r[k] = v
    end
    return r
end

function MB.AddRule(fields, atTop)
    local r = MB.NewRule(fields)
    if atTop then
        table.insert(D().rules, 1, r)
    else
        table.insert(D().rules, r)
    end
    ns.Fire("MAIL")
    return r
end

function MB.FindRule(id)
    for i, r in ipairs(D().rules) do
        if r.id == id then
            return r, i
        end
    end
end

-- Saves an edited rule. Returns true, or false and why not.
function MB.SaveRule(id, fields)
    local r = MB.FindRule(id)
    if not r then
        return false, "That rule is gone."
    end
    local keep = floor(tonumber(fields.keep) or r.keep or 0)
    if keep < 0 or keep > 99999 then
        return false, "Keep must be between 0 and 99999."
    end
    if fields.item ~= nil or fields.cat ~= nil then
        if fields.item then
            r.item, r.cat = tonumber(fields.item), nil
        else
            if not MB.CAT[fields.cat] then
                return false, "Unknown category."
            end
            r.cat, r.item = fields.cat, nil
        end
    end
    if fields.to ~= nil then
        if fields.to ~= "banker" and not ns.db.chars[fields.to] then
            return false, "Unknown character."
        end
        r.to = fields.to
    end
    if fields.scope ~= nil then
        r.scope = fields.scope
    end
    if fields.on ~= nil then
        r.on = fields.on and true or false
    end
    r.keep = keep
    ns.Fire("MAIL")
    return true
end

function MB.DeleteRule(id)
    local _, i = MB.FindRule(id)
    if i then
        table.remove(D().rules, i)
        ns.Fire("MAIL")
        return true
    end
    return false
end

function MB.MoveRule(id, dir)
    local list = D().rules
    local _, i = MB.FindRule(id)
    local j = i and (i + dir)
    if not i or j < 1 or j > #list then
        return false
    end
    list[i], list[j] = list[j], list[i]
    ns.Fire("MAIL")
    return true
end

function MB.SetRuleOn(id, on)
    local r = MB.FindRule(id)
    if r then
        r.on = on and true or false
        ns.Fire("MAIL")
    end
end

-- Suggested starting rules. Added switched OFF for you to review; never
-- switched on here. A preset whose character isn't on this realm is added
-- without a recipient (it can't run until you pick one).
MB.PRESETS = {
    { cat = "cloth", name = "Xeon Hexspark", keep = 20 },
    { cat = "herbs", name = "Xeon Raincaller", keep = 5 },
    { cat = "metal", name = "Xeon Mana", keep = 20 },
    { cat = "leather", name = "Xeon Ironfang", keep = 10 },
    { cat = "stock", banker = true, keep = 0 },
}

local function keyByName(name)
    for key, c in pairs(ns.db.chars or {}) do
        if c.realmKey == ns.realmKey and sameName(c.name, name) then
            return key
        end
    end
    return nil
end

function MB.AddPresets()
    local added = 0
    for _, p in ipairs(MB.PRESETS) do
        local have = false
        for _, r in ipairs(D().rules) do
            if r.cat == p.cat then
                have = true
            end
        end
        if not have then
            local to = p.banker and "banker" or keyByName(p.name)
            local r = MB.NewRule({ cat = p.cat, keep = p.keep, on = false, scope = "account",
                preset = p.name or "Banker" })
            r.to = to -- nil when that character isn't known here: it waits for you to pick one
            table.insert(D().rules, r)
            added = added + 1
        end
    end
    ns.Fire("MAIL")
    return added
end

----------------------------------------------------------------------
-- "Always keep" list: items no rule or quick-send ever mails
----------------------------------------------------------------------

function MB.IsKept(id)
    local k = O().mailKeep
    return k and k[id] and true or false
end

function MB.SetKept(id, on)
    if type(O().mailKeep) ~= "table" then
        O().mailKeep = {}
    end
    O().mailKeep[id] = on and true or nil
    ns.Fire("MAIL")
end

-- Items you took the banker mark off (bag window): nothing but an item rule
-- of their own sends them to your banker - not a group rule (Herbs, Auction
-- stock...) and not quick-send's own picks. Marking it again lifts this.
function MB.IsBankerBlocked(id)
    local b = O().mailNoBanker
    return type(b) == "table" and b[id] == true
end

function MB.SetBankerBlocked(id, on)
    if type(O().mailNoBanker) ~= "table" then
        O().mailNoBanker = {}
    end
    O().mailNoBanker[id] = on and true or nil
    ns.Fire("MAIL")
end

local function toBanker(r)
    return r.to == "banker" or (r.to ~= nil and r.to == MB.BankerKey())
end

----------------------------------------------------------------------
-- Bags, read live (never from the saved copy: this is about what's in the
-- bags right now)
----------------------------------------------------------------------

local function lastBag()
    return (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
end

-- items[id] = { id, total, mailable, stacks = { mailable stacks }, why = reason
-- some aren't mailable }, plus the full list of stacks.
function MB.ScanBags()
    local items, all = {}, {}
    if not C_Container or not C_Container.GetContainerNumSlots then
        return items, all
    end
    for bag = 0, lastBag() do
        for slot = 1, ns.try(C_Container.GetContainerNumSlots, bag) or 0 do
            local info = ns.try(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID then
                local s = { bag = bag, slot = slot, id = info.itemID, count = info.stackCount or 1,
                    locked = info.isLocked and true or false, bound = info.isBound and true or false }
                local q = ns.try(C_Container.GetContainerItemQuestInfo, bag, slot)
                local quest = type(q) == "table" and (q.isQuestItem or q.questID ~= nil) or false
                local it = ns.Item(s.id)
                if it and it.c == 12 then
                    quest = true
                end
                s.why = (s.bound and "bound") or (quest and "quest item") or (s.locked and "locked") or nil
                all[#all + 1] = s
                local e = items[s.id]
                if not e then
                    e = { id = s.id, total = 0, mailable = 0, stacks = {} }
                    items[s.id] = e
                end
                e.total = e.total + s.count
                if s.why then
                    e.why = e.why or s.why
                else
                    e.mailable = e.mailable + s.count
                    e.stacks[#e.stacks + 1] = s
                end
            end
        end
    end
    return items, all
end

local function freeSlots()
    local n = C_Container and ns.try(C_Container.CalculateTotalNumberOfFreeBagSlots)
    return n
end

-- The whole stacks to send for up to `cap` items: as many as possible
-- without going over (mail sends whole stacks; it never splits one).
-- Returns stacks, total.
local function pickStacks(stacks, cap)
    local list = {}
    for _, s in ipairs(stacks) do
        if s.count > 0 then
            list[#list + 1] = s
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        if a.bag ~= b.bag then
            return a.bag < b.bag
        end
        return a.slot < b.slot
    end)
    cap = floor(cap or 0)
    if cap <= 0 or #list == 0 then
        return {}, 0
    end
    local sum = 0
    for _, s in ipairs(list) do
        sum = sum + s.count
    end
    if sum <= cap then
        return list, sum
    end
    if cap > 5000 or #list > 60 then
        -- Big numbers: biggest stacks first, as many as fit.
        local out, total = {}, 0
        for _, s in ipairs(list) do
            if total + s.count <= cap then
                out[#out + 1] = s
                total = total + s.count
            end
        end
        return out, total
    end
    -- Small numbers: the best total that fits exactly (0/1 knapsack on counts).
    local from = { [0] = false }
    for i, s in ipairs(list) do
        for t = cap, s.count, -1 do
            if from[t] == nil and from[t - s.count] ~= nil then
                from[t] = { prev = t - s.count, i = i }
            end
        end
    end
    local best = cap
    while best > 0 and from[best] == nil do
        best = best - 1
    end
    local out, t = {}, best
    while t > 0 do
        local f = from[t]
        out[#out + 1] = list[f.i]
        t = f.prev
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out, best
end
MB.PickStacks = pickStacks

----------------------------------------------------------------------
-- Who owns each item: the rules, applied in order
----------------------------------------------------------------------

-- For every item in `items` (from ScanBags): { id, total, mailable, why,
-- kept, rule, ruleIndex, to, toName, problem, keep, sendable, qty, stacks }.
-- `rules` defaults to the enabled rules that apply to this character.
function MB.Allocate(items, rules)
    rules = rules or MB.ActiveRules()
    local out = {}
    for id, e in pairs(items) do
        local a = { id = id, total = e.total, mailable = e.mailable, why = e.why, qty = 0, stacks = {} }
        if MB.IsKept(id) then
            a.kept = true
        else
            local blocked = MB.IsBankerBlocked(id)
            for i, r in ipairs(rules) do
                if MB.RuleMatches(r, id) and not (blocked and not r.item and toBanker(r)) then
                    a.rule, a.ruleIndex = r, i
                    break
                end
            end
            if a.rule then
                a.to, a.toName, a.problem = MB.RuleTarget(a.rule)
                a.keep = max(0, a.rule.keep or 0)
                -- Keep is a total across every stack, mailable or not.
                a.sendable = max(0, min(e.total - a.keep, e.mailable))
                if not a.problem then
                    a.stacks, a.qty = pickStacks(e.stacks, a.sendable)
                end
            end
        end
        out[id] = a
    end
    return out
end

-- Materials a profitable recipe this character knows uses: quick-send leaves
-- them alone. Returns { [itemID] = recipe evaluation }.
function MB.CraftReserved()
    local out = {}
    local ok, list = pcall(ns.CraftList)
    if not ok or type(list) ~= "table" then
        return out
    end
    for _, e in ipairs(list.good or {}) do
        if e.rec and e.rec.mine then
            for _, r in ipairs(e.rec.reagents or {}) do
                if not out[r[1]] then
                    out[r[1]] = e
                end
            end
        end
    end
    return out
end

-- Things the Sell advice says to auction (or you ticked to sell), and not
-- unticked by you.
function MB.AuctionStock()
    local out = {}
    local ok, advice = pcall(ns.BagAdvice)
    if ok and type(advice) == "table" then
        for _, row in ipairs(advice.ah or {}) do
            if postPick(row.id) ~= false then
                out[row.id] = "advice"
            end
        end
    end
    for id, on in pairs(O().postPick or {}) do
        if on == true then
            out[id] = "ticked"
        end
    end
    return out
end

----------------------------------------------------------------------
-- Plans
--
-- plan = { mode = "banker" | "rules" | "custom", lines = { line }, ships =
--          { shipment }, skipped = { {id, why} }, items, postage, gold,
--          problem = text that stops the whole plan, warn = text }
-- line = { id, to, toName, qty, total, mailable, keep, stacks, why, rule,
--          excluded }
-- shipment = { to, name, atts = { {id, count, bag, slot} }, items =
--          { {id, qty} }, keep = { [id] = keep }, money, cod, subject, body,
--          postage, status, n, of }
----------------------------------------------------------------------

local function itemSort(a, b)
    if (a.order or 0) ~= (b.order or 0) then
        return (a.order or 0) < (b.order or 0)
    end
    return ns.ItemName(a.id) < ns.ItemName(b.id)
end

local function subjectFor(ship, mode)
    local first = ship.items[1]
    local text
    if not first then
        text = "Gold"
    else
        text = ns.ItemName(first.id) .. (first.qty > 1 and (" x" .. first.qty) or "")
        if #ship.items > 1 then
            text = text .. " and " .. plural(#ship.items - 1, "more")
        end
    end
    if ship.of and ship.of > 1 then
        text = text .. " (" .. ship.n .. "/" .. ship.of .. ")"
    end
    return (mode == "banker" and "Auction stock: " or "Supplies: ") .. text
end

-- Splits the plan's lines into mails: one recipient per mail, at most the
-- client's attachment limit each.
local function buildShips(plan)
    local order, by = {}, {}
    for _, l in ipairs(plan.lines) do
        if not l.excluded and l.qty > 0 and l.to then
            local g = by[l.to]
            if not g then
                g = { to = l.to, name = l.toName, atts = {}, keep = {} }
                by[l.to] = g
                order[#order + 1] = g
            end
            g.keep[l.id] = l.keep or 0
            for _, s in ipairs(l.stacks) do
                g.atts[#g.atts + 1] = { id = l.id, count = s.count, bag = s.bag, slot = s.slot }
            end
        end
    end
    local ships = {}
    local limit = MB.MaxAttach()
    for _, g in ipairs(order) do
        local chunks = {}
        for i, a in ipairs(g.atts) do
            local c = floor((i - 1) / limit) + 1
            chunks[c] = chunks[c] or {}
            table.insert(chunks[c], a)
        end
        for n, atts in ipairs(chunks) do
            local sums, list = {}, {}
            for _, a in ipairs(atts) do
                if not sums[a.id] then
                    sums[a.id] = { id = a.id, qty = 0 }
                    list[#list + 1] = sums[a.id]
                end
                sums[a.id].qty = sums[a.id].qty + a.count
            end
            ships[#ships + 1] = { to = g.to, name = g.name, atts = atts, items = list, keep = g.keep, money = 0,
                cod = 0, body = "", n = n, of = #chunks, postage = MB.Postage(#atts), status = "planned" }
        end
    end
    for _, s in ipairs(ships) do
        s.subject = subjectFor(s, plan.mode)
    end
    plan.ships = ships
end

local function totals(plan)
    local items, postage = 0, 0
    for _, s in ipairs(plan.ships) do
        for _, a in ipairs(s.atts) do
            items = items + a.count
        end
        postage = postage + s.postage
    end
    plan.items, plan.postage = items, postage
    local money = ns.try(GetMoney) or 0
    plan.after = money - postage - (plan.gold or 0)
    if #plan.ships > 0 and money - postage < MB.Reserve() then
        plan.warn = "Postage (" .. plain(postage) .. ") " .. shortWords()
            .. (MB.Reserve() > 0 and ". Lower \"Keep at least\" or send less." or ". Send less.")
    end
end

local function newPlan(mode)
    return { mode = mode, lines = {}, ships = {}, skipped = {}, items = 0, postage = 0, gold = 0, built = GetTime() }
end

local function lineFrom(a, order)
    return { id = a.id, to = a.to, toName = a.toName, qty = a.qty, total = a.total, mailable = a.mailable,
        keep = a.keep or 0, sendable = a.sendable, stacks = a.stacks, why = a.why, rule = a.rule,
        excluded = MB.exclude[a.id] and true or false, order = order or 0 }
end

-- Every rule, applied to your bags: what goes where.
function MB.PlanRules(rules)
    local plan = newPlan("rules")
    local items = MB.ScanBags()
    local alloc = MB.Allocate(items, rules)
    for id, a in pairs(alloc) do
        if a.rule then
            if a.problem then
                plan.skipped[#plan.skipped + 1] = { id = id, why = a.problem, rule = a.rule, toName = a.toName }
            elseif a.qty > 0 then
                plan.lines[#plan.lines + 1] = lineFrom(a, a.ruleIndex)
            elseif a.mailable <= 0 then
                plan.skipped[#plan.skipped + 1] = { id = id, why = a.why or "unmailable", rule = a.rule, toName = a.toName }
            elseif a.sendable <= 0 then
                plan.skipped[#plan.skipped + 1] = { id = id, why = "keep", rule = a.rule, toName = a.toName }
            else
                plan.skipped[#plan.skipped + 1] = { id = id, why = "stacks", rule = a.rule, toName = a.toName }
            end
        end
    end
    table.sort(plan.lines, itemSort)
    buildShips(plan)
    totals(plan)
    return plan
end

-- Quick-send: auction stock (and any categories you added to quick-send) to
-- your banker. Materials your profitable recipes use stay, and anything a
-- rule sends somewhere else stays out of it.
function MB.PlanBanker()
    local plan = newPlan("banker")
    local banker = MB.BankerKey()
    plan.banker = banker
    if not banker then
        plan.problem = "Pick your banker first (the gear button above)."
        return plan
    end
    if banker == ns.charKey then
        plan.problem = "You are the banker. There's nothing to send to yourself."
        return plan
    end
    local bankerName = MB.NameOf(banker)
    local items = MB.ScanBags()
    local alloc = MB.Allocate(items)
    local reserved = MB.CraftReserved()
    local stock = MB.AuctionStock()
    local cats = O().mailQuickCats or {}
    for id, a in pairs(alloc) do
        if a.kept then
            -- your "always keep" list
        elseif a.rule then
            if a.to == banker and not a.problem then
                if a.qty > 0 then
                    plan.lines[#plan.lines + 1] = lineFrom(a, 1)
                end
            elseif a.qty > 0 or a.problem == "self" then
                plan.skipped[#plan.skipped + 1] = { id = id, why = "rule", rule = a.rule, toName = a.toName }
            end
        else
            local blocked = MB.IsBankerBlocked(id)
            local why = not blocked and stock[id] or nil
            if not why and not blocked then
                for key, on in pairs(cats) do
                    if on and MB.InCategory(key, id) then
                        why = "cat:" .. key
                    end
                end
            end
            if why then
                if reserved[id] and postPick(id) ~= true then
                    plan.skipped[#plan.skipped + 1] = { id = id, why = "craft", recipe = reserved[id] }
                elseif a.mailable <= 0 then
                    plan.skipped[#plan.skipped + 1] = { id = id, why = a.why or "unmailable" }
                else
                    local e = items[id]
                    local stacks, qty = pickStacks(e.stacks, e.mailable)
                    local l = lineFrom({ id = id, to = banker, toName = bankerName, qty = qty, total = e.total,
                        mailable = e.mailable, keep = 0, sendable = e.mailable, stacks = stacks, why = e.why }, 2)
                    l.reason = why
                    plan.lines[#plan.lines + 1] = l
                end
            end
        end
    end
    table.sort(plan.lines, itemSort)
    buildShips(plan)
    -- Spare gold: optional, off by default, never below your reserve after
    -- every mail's postage.
    if O().mailGold then
        local money = ns.try(GetMoney) or 0
        local postage = 0
        for _, s in ipairs(plan.ships) do
            postage = postage + s.postage
        end
        if #plan.ships == 0 then
            postage = MB.Postage(0)
        end
        local spare = money - MB.Reserve() - postage
        if spare > 0 then
            plan.gold = spare
            local last
            for _, s in ipairs(plan.ships) do
                if s.to == banker then
                    last = s
                end
            end
            if not last then
                last = { to = banker, name = bankerName, atts = {}, items = {}, keep = {}, money = 0, cod = 0, body = "",
                    n = 1, of = 1, postage = MB.Postage(0), status = "planned" }
                last.subject = "Gold from " .. myName()
                plan.ships[#plan.ships + 1] = last
            end
            last.money = spare
            last.gold = true
        else
            plan.goldNote = "No spare gold: you have " .. plain(money)
                .. (MB.Reserve() > 0 and (", keep " .. plain(MB.Reserve())) or "")
                .. " and postage is " .. plain(postage) .. "."
        end
    end
    totals(plan)
    return plan
end

-- A mail you write yourself. form = { to = name, subject, body, money,
-- cod, picks = { ["bag:slot"] = true } }
function MB.PlanCustom(form)
    local plan = newPlan("custom")
    form = form or {}
    local to = form.to and form.to:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if to == "" then
        plan.problem = "Who is it for?"
    elseif MB.IsSelf(nil, to) then
        plan.problem = "That's you. Pick someone else."
    end
    local key = keyByName(to)
    local _, stacks = MB.ScanBags()
    local atts, sums, list = {}, {}, {}
    for _, s in ipairs(stacks) do
        if form.picks and form.picks[s.bag .. ":" .. s.slot] then
            if s.why then
                plan.skipped[#plan.skipped + 1] = { id = s.id, why = s.why }
            else
                atts[#atts + 1] = { id = s.id, count = s.count, bag = s.bag, slot = s.slot }
                if not sums[s.id] then
                    sums[s.id] = { id = s.id, qty = 0 }
                    list[#list + 1] = sums[s.id]
                end
                sums[s.id].qty = sums[s.id].qty + s.count
            end
        end
    end
    if #atts > MB.MaxAttach() then
        plan.problem = "A mail holds at most " .. MB.MaxAttach() .. " stacks. You picked " .. #atts .. "."
    end
    local money = max(0, floor(tonumber(form.money) or 0))
    local cod = 0
    if form.cod then
        cod, money = money, 0
        if cod > 0 and #atts == 0 then
            plan.problem = plan.problem or "C.O.D. needs at least one attachment."
        end
        if cod > 0 and C_Mail and C_Mail.IsCODEnabled and not ns.try(C_Mail.IsCODEnabled) then
            plan.problem = plan.problem or "This client has C.O.D. switched off."
        end
    end
    if not plan.problem and #atts == 0 and money == 0 and (form.subject or "") == "" then
        plan.problem = "Add a subject, an attachment or some gold."
    end
    local ship = { to = key or to, name = to, custom = not key, atts = atts, items = list, keep = {}, money = money,
        cod = cod, subject = (form.subject and form.subject ~= "") and form.subject or nil, body = form.body or "",
        n = 1, of = 1, postage = MB.Postage(#atts), status = "planned", exact = true }
    if not ship.subject then
        ship.subject = #list > 0 and subjectFor(ship, "custom") or "(no subject)"
    end
    plan.gold = money
    if not plan.problem then
        plan.ships = { ship }
        local have = ns.try(GetMoney) or 0
        if money > 0 and have - money - ship.postage < MB.Reserve() then
            plan.problem = "Sending " .. plain(money) .. " plus " .. plain(ship.postage) .. " postage "
                .. shortWords() .. "."
            plan.ships = {}
        end
    end
    for _, a in ipairs(atts) do
        plan.lines[#plan.lines + 1] = { id = a.id, to = ship.to, toName = to, qty = a.count, total = a.count,
            mailable = a.count, keep = 0, stacks = { a }, order = 0 }
    end
    totals(plan)
    return plan
end

----------------------------------------------------------------------
-- The inbox
----------------------------------------------------------------------

local function fingerprint(m)
    return { sender = m.sender or "", subject = m.subject or "", cod = m.cod or 0, days = m.days or 0 }
end

local function sameMail(m, fp)
    return (m.sender or "") == fp.sender and (m.subject or "") == fp.subject and (m.cod or 0) == fp.cod
        and math.abs((m.days or 0) - fp.days) < 0.05
end

local function readMail(i)
    local _, stationery, sender, subject, money, cod, days, itemCount, wasRead, returned, textCreated, canReply,
        isGM, firstQty, firstLink = GetInboxHeaderInfo(i)
    local m = { index = i, stationery = stationery, sender = sender or "Unknown", subject = subject or "",
        money = money or 0, cod = cod or 0, days = days or 0, itemCount = itemCount or 0, read = wasRead and true or false,
        returned = returned and true or false, textCreated = textCreated, canReply = canReply, gm = isGM and true or false,
        firstQty = firstQty, firstLink = firstLink, items = {} }
    if type(GetInboxInvoiceInfo) == "function" then
        local ok, kind = pcall(GetInboxInvoiceInfo, i)
        if ok then
            m.invoice = kind
        end
    end
    if (m.itemCount or 0) > 0 and type(HasInboxItem) == "function" then
        for a = 1, maxReceive() do
            if ns.try(HasInboxItem, i, a) then
                local name, id, texture, count, quality, canUse = GetInboxItem(i, a)
                m.items[#m.items + 1] = { a = a, name = name, id = id, icon = texture, count = count or 1,
                    quality = quality, canUse = canUse }
            end
        end
    end
    if m.cod > 0 then
        m.restricted = "cod"
    elseif m.gm then
        m.restricted = "gm"
    elseif m.invoice == "seller_temp_invoice" then
        m.restricted = "pending"
    end
    m.fp = fingerprint(m)
    return m
end

local function readInbox()
    local list = {}
    if type(GetInboxNumItems) ~= "function" then
        MB.inbox = list
        return list
    end
    local shown, total = GetInboxNumItems()
    shown, total = shown or 0, total or shown or 0
    for i = 1, shown do
        local ok, m = pcall(readMail, i)
        if ok and m then
            list[#list + 1] = m
        end
    end
    MB.inbox, MB.numShown, MB.numTotal = list, shown, total
    return list
end
MB.ReadInbox = readInbox

function MB.InboxTotals()
    local money, items, cod = 0, 0, 0
    for _, m in ipairs(MB.inbox) do
        if not m.restricted then
            money = money + m.money
        end
        for _, it in ipairs(m.items) do
            items = items + (it.count or 1)
        end
        if m.restricted == "cod" then
            cod = cod + 1
        end
    end
    return money, items, cod
end

-- The mail's letter text. Reading it marks the mail as read, the same as
-- opening it in the game's mailbox.
function MB.Body(m)
    if not m or type(GetInboxText) ~= "function" then
        return ""
    end
    local cur = MB.inbox[m.index]
    if not cur or not sameMail(cur, m.fp) then
        return ""
    end
    local text = ns.try(GetInboxText, m.index)
    return text or ""
end

-- Why bulk collecting leaves this mail alone, or nil.
function MB.BulkSkipReason(m)
    if m.restricted == "cod" then
        return "C.O.D.: open it in the game's mailbox to pay"
    elseif m.restricted == "gm" then
        return "From a Game Master: open it yourself"
    elseif m.restricted == "pending" then
        return "Sale pending: the gold arrives later"
    end
    return nil
end

----------------------------------------------------------------------
-- The queue
----------------------------------------------------------------------

local Q = { mode = nil, op = nil, token = 0, ships = nil, i = 0, failed = {}, got = { money = 0, items = 0 } }
MB.Q = Q

-- "collect" | "send" | nil, and the command that's with the server (or nil).
function MB.Busy()
    return Q.mode, Q.op
end

local function serverBusy()
    if C_Mail and C_Mail.IsCommandPending then
        return ns.try(C_Mail.IsCommandPending) and true or false
    end
    return false
end

-- Calls one of the game's mail functions as ourselves (the hooks below
-- ignore these).
local function call(fn, ...)
    MB.selfCall = true
    local ok, a, b = pcall(fn, ...)
    MB.selfCall = false
    if not ok then
        ns.Err("mail", a)
    end
    return ok, a, b
end

local function later(delay, fn)
    local token = Q.token
    C_Timer.After(delay, ns.Guard("mail-queue", function()
        if token == Q.token then
            fn()
        end
    end))
end

local function newToken()
    Q.token = Q.token + 1
end

----------------------------------------------------------------------
-- Taking mail
----------------------------------------------------------------------

local function bagCount(id)
    local n = 0
    if not id or not C_Container then
        return 0
    end
    for bag = 0, lastBag() do
        for slot = 1, ns.try(C_Container.GetContainerNumSlots, bag) or 0 do
            local info = ns.try(C_Container.GetContainerItemInfo, bag, slot)
            if type(info) == "table" and info.itemID == id then
                n = n + (info.stackCount or 1)
            end
        end
    end
    return n
end
MB.BagCount = bagCount

-- How much of `what` is still in mails that look like this one (two auction
-- mails can be identical, so the check is over all of them).
local function stillInMail(fp, what, id)
    local n = 0
    for _, m in ipairs(readInbox()) do
        if sameMail(m, fp) then
            if what == "money" then
                n = n + m.money
            else
                for _, it in ipairs(m.items) do
                    if it.id == id then
                        n = n + (it.count or 1)
                    end
                end
            end
        end
    end
    return n
end

local collectStep

local function finishCollect(kind, text)
    Q.mode, Q.op, Q.only = nil, nil, nil
    newToken()
    setStatus(kind, text)
end

local function collectSummary()
    local parts = {}
    if Q.got.money > 0 then
        parts[#parts + 1] = plain(Q.got.money)
    end
    if Q.got.items > 0 then
        parts[#parts + 1] = plural(Q.got.items, "item")
    end
    return #parts > 0 and ("Collected " .. table.concat(parts, " and ") .. ".") or "Nothing was collected."
end

-- The next thing to take: { m, what = "money" | "item", a, id, count }.
local function nextTake()
    local only = Q.only
    local free = freeSlots()
    local bagsFull = false
    for _, m in ipairs(readInbox()) do
        local key = m.fp.sender .. "|" .. m.fp.subject
        if only then
            if sameMail(m, only.fp) then
                if only.what == "money" and m.money > 0 then
                    return { m = m, what = "money" }
                elseif only.what == "item" then
                    for _, it in ipairs(m.items) do
                        if it.a == only.a then
                            if free == 0 then
                                return nil, "Your bags are full."
                            end
                            return { m = m, what = "item", a = it.a, id = it.id, count = it.count }
                        end
                    end
                end
            end
        elseif not m.restricted then
            if m.money > 0 and not Q.failed[key .. "|money"] then
                return { m = m, what = "money" }
            end
            if not Q.goldOnly then
                for _, it in ipairs(m.items) do
                    if not Q.failed[key .. "|" .. tostring(it.id)] then
                        if free == 0 then
                            bagsFull = true
                        else
                            return { m = m, what = "item", a = it.a, id = it.id, count = it.count }
                        end
                    end
                end
            end
        end
    end
    if bagsFull then
        return nil, "Your bags are full. Make room and collect again."
    end
    return nil
end

local function takeDone(op)
    if op.what == "money" then
        if (ns.try(GetMoney) or 0) > op.beforeMoney then
            return true
        end
    elseif bagCount(op.id) > op.beforeBag then
        return true
    end
    return stillInMail(op.fp, op.what, op.id) < op.before
end

local function takeResolved(op, ok, note)
    if Q.op ~= op then
        return
    end
    Q.op = nil
    if ok then
        if op.what == "money" then
            Q.got.money = Q.got.money + op.amount
        else
            Q.got.items = Q.got.items + (op.count or 1)
        end
    else
        Q.failed[op.key] = true
        Q.skippedTakes = (Q.skippedTakes or 0) + 1
        Q.lastProblem = note
    end
    if Q.stopAfter then
        local why = Q.stopWhy or "Stopped."
        Q.stopAfter, Q.stopWhy = nil, nil
        finishCollect("error", collectSummary() .. " " .. why)
        return
    end
    if Q.only then
        if ok then
            finishCollect("done", op.what == "money" and ("Took " .. plain(op.amount) .. ".")
                or ("Took " .. (op.count or 1) .. " x " .. ns.ItemName(op.id) .. "."))
        else
            finishCollect("error", note or "The server said no.")
        end
        return
    end
    later(PACE, collectStep)
end

local function checkTake()
    local op = Q.op
    if op and (op.what == "money" or op.what == "item") and takeDone(op) then
        takeResolved(op, true)
    end
end

collectStep = function()
    if Q.mode ~= "collect" or Q.op then
        return
    end
    if not MB.open then
        finishCollect("error", collectSummary() .. " The mailbox closed, so collecting stopped.")
        return
    end
    if serverBusy() then
        Q.busyTicks = (Q.busyTicks or 0) + 1
        if Q.busyTicks > BUSY_LIMIT then
            finishCollect("error", collectSummary() .. " The server stayed busy, so collecting stopped. Try again in a moment.")
            return
        end
        setStatus("waiting", "Waiting for the server...")
        later(PACE, collectStep)
        return
    end
    Q.busyTicks = 0
    local t, problem = nextTake()
    if not t then
        local text = collectSummary()
        if Q.skippedTakes and Q.skippedTakes > 0 then
            text = text .. " " .. plural(Q.skippedTakes, "attachment") .. " couldn't be taken"
                .. (Q.lastProblem and (" (" .. Q.lastProblem .. ")") or "") .. "."
        end
        if problem then
            finishCollect("error", text .. " " .. problem)
        else
            finishCollect("done", text)
        end
        return
    end
    local m = t.m
    local op = { what = t.what, fp = m.fp, index = m.index, a = t.a, id = t.id, count = t.count, amount = m.money,
        beforeMoney = ns.try(GetMoney) or 0, beforeBag = t.id and bagCount(t.id) or 0, at = GetTime(),
        key = m.fp.sender .. "|" .. m.fp.subject .. "|" .. (t.what == "money" and "money" or tostring(t.id)) }
    op.before = stillInMail(m.fp, t.what, t.id)
    Q.op = op
    if t.what == "money" then
        call(TakeInboxMoney, m.index)
        setStatus("waiting", "Taking " .. plain(m.money) .. " from \"" .. m.subject .. "\"... waiting for the server")
    else
        call(TakeInboxItem, m.index, t.a)
        setStatus("waiting", "Taking " .. (t.count or 1) .. " x " .. ns.ItemName(t.id) .. "... waiting for the server")
    end
    later(TAKE_TIMEOUT, function()
        if Q.op ~= op then
            return
        end
        if op.confirm and GetTime() - op.at < CONFIRM_TIMEOUT then
            later(1, function() if Q.op == op then checkTake() end end)
            return
        end
        if takeDone(op) then
            takeResolved(op, true)
        else
            -- Nothing changed: it wasn't taken. Stop rather than hammer the server.
            Q.stopAfter, Q.stopWhy = true, "The server didn't answer, so collecting stopped. Nothing was retried."
            takeResolved(op, false, "no answer")
        end
    end)
end

local function startCollect(goldOnly, only)
    if not MB.open then
        return false, "Open a mailbox first."
    end
    if Q.mode then
        return false, Q.mode == "send" and "Busy sending mail. Wait for it to finish." or "Already collecting."
    end
    Q.mode, Q.op, Q.only, Q.goldOnly = "collect", nil, only, goldOnly
    Q.failed, Q.got, Q.skippedTakes, Q.lastProblem, Q.stopAfter, Q.busyTicks = {}, { money = 0, items = 0 }, 0, nil, nil, 0
    newToken()
    setStatus("working", only and "Taking it..." or (goldOnly and "Collecting gold..." or "Collecting mail..."))
    collectStep()
    return true
end

-- Everything that's safe to take: gold and items from every mail that isn't
-- C.O.D., from a GM, or a sale still pending. Never pays, returns or deletes.
function MB.CollectAll()
    return startCollect(false)
end

function MB.CollectGold()
    return startCollect(true)
end

-- One attachment (or the gold) of the mail you picked.
function MB.TakeAttachment(m, a)
    if not m then
        return false, "Pick a mail."
    end
    if m.restricted == "cod" then
        return false, "This is C.O.D. Open the game's mailbox to pay for it."
    end
    return startCollect(false, { fp = m.fp, what = "item", a = a })
end

function MB.TakeMoney(m)
    if not m or (m.money or 0) <= 0 then
        return false, "There's no gold in this mail."
    end
    if m.restricted == "cod" then
        return false, "This is C.O.D. Open the game's mailbox to pay for it."
    end
    return startCollect(false, { fp = m.fp, what = "money" })
end

----------------------------------------------------------------------
-- Sending mail
----------------------------------------------------------------------

local function clearAttachments()
    if type(HasSendMailItem) ~= "function" or type(ClickSendMailItemButton) ~= "function" then
        return
    end
    for i = 1, tonumber(ATTACHMENTS_MAX) or 16 do
        if ns.try(HasSendMailItem, i) then
            call(ClickSendMailItemButton, i, true)
        end
    end
    if ClearCursor then
        pcall(ClearCursor)
    end
end

local function sendShowing(on)
    if type(SetSendMailShowing) == "function" then
        call(SetSendMailShowing, on)
    end
end

local function currentShip()
    return Q.ships and Q.ships[Q.i]
end

function MB.Shipments()
    return Q.ships, Q.i
end

local function remainingPostage(after)
    local n = 0
    for j = after + 1, #(Q.ships or {}) do
        local s = Q.ships[j]
        if s.status == "planned" then
            n = n + s.postage
        end
    end
    return n
end

local function shipLabel(s)
    return "mail " .. Q.i .. " of " .. #Q.ships .. " to " .. (s.name or "?")
end

local function stopSending(kind, text)
    local s = currentShip()
    if s and (s.status == "ready" or s.status == "preparing") then
        clearAttachments()
        s.status = "planned"
    end
    sendShowing(false)
    Q.mode, Q.op = nil, nil
    newToken()
    setStatus(kind, text)
end

-- Re-reads the bags for one mail and picks the stacks again: an item may
-- have moved, been used or sold since the preview. Quantities only ever go
-- down. Returns attachments, notes about what changed.
local function revalidate(s)
    local items = MB.ScanBags()
    local atts, notes = {}, {}
    local limit = MB.MaxAttach()
    -- The original stacks, if every one of them is still exactly there.
    local exact = true
    for _, a in ipairs(s.atts) do
        local info = ns.try(C_Container.GetContainerItemInfo, a.bag, a.slot)
        if type(info) ~= "table" or info.itemID ~= a.id or (info.stackCount or 1) ~= a.count or info.isLocked
            or info.isBound then
            exact = false
            break
        end
    end
    local wanted = {}
    for _, it in ipairs(s.items) do
        wanted[#wanted + 1] = it
    end
    for _, it in ipairs(wanted) do
        local e = items[it.id]
        local keep = s.keep and s.keep[it.id] or 0
        local allowed = e and max(0, min(e.total - keep, e.mailable)) or 0
        local cap = min(it.qty, allowed)
        local picked, got
        if exact and allowed >= it.qty then
            picked, got = {}, 0
            for _, a in ipairs(s.atts) do
                if a.id == it.id then
                    picked[#picked + 1] = a
                    got = got + a.count
                end
            end
        else
            picked, got = pickStacks(e and e.stacks or {}, cap)
        end
        if got < it.qty then
            notes[#notes + 1] = ns.ItemName(it.id) .. ": " .. got .. " instead of " .. it.qty
        end
        for _, p in ipairs(picked) do
            if #atts < limit then
                atts[#atts + 1] = { id = it.id, count = p.count, bag = p.bag, slot = p.slot }
            end
        end
    end
    return atts, notes
end

local function attachmentsMatch(atts)
    if type(GetSendMailItem) ~= "function" then
        return false
    end
    for j = 1, tonumber(ATTACHMENTS_MAX) or 16 do
        local want = atts[j]
        local has = ns.try(HasSendMailItem, j)
        if want then
            if not has then
                return false
            end
            local _, id, _, count = GetSendMailItem(j)
            if id ~= want.id or (count or 1) ~= want.count then
                return false
            end
        elseif has then
            return false
        end
    end
    return true
end

local prepare

local function advance()
    if Q.stopAfter then
        local why = Q.stopWhy or "Stopped. Nothing more was sent."
        Q.stopAfter, Q.stopWhy = nil, nil
        stopSending("error", why)
        return
    end
    Q.i = Q.i + 1
    while Q.ships[Q.i] and Q.ships[Q.i].status ~= "planned" do
        Q.i = Q.i + 1
    end
    if not Q.ships[Q.i] then
        local sent, bad = 0, 0
        for _, s in ipairs(Q.ships) do
            if s.status == "sent" then
                sent = sent + 1
            elseif s.status ~= "skipped" then
                bad = bad + 1
            end
        end
        Q.i = #Q.ships
        local fresh = sent > 0 and bad == 0
        stopSending(bad > 0 and "error" or "done",
            (sent > 0 and ("Sent " .. plural(sent, "mail") .. ". ") or "")
            .. (bad > 0 and (plural(bad, "mail") .. " didn't go. See the list.")
                or (fresh and "All done. Showing a new preview of what's left in your bags.") or "All done."))
        if fresh then
            -- Everything went: straight on to a fresh preview (a failed one
            -- keeps the list up so you can see which).
            Q.ships, Q.i, Q.plan = nil, 0, nil
            ns.Fire("MAIL")
        end
        return
    end
    later(PACE, prepare)
end

-- Puts the next mail's attachments on, checks them, and waits for your click.
prepare = function()
    local s = currentShip()
    if Q.mode ~= "send" or not s or Q.op then
        return
    end
    if not MB.open then
        stopSending("error", "The mailbox closed. Nothing more was sent.")
        return
    end
    if serverBusy() then
        Q.busyTicks = (Q.busyTicks or 0) + 1
        if Q.busyTicks > BUSY_LIMIT then
            stopSending("error", "The server stayed busy. Nothing more was sent; press Send again in a moment.")
            return
        end
        setStatus("waiting", "Waiting for the server before " .. shipLabel(s) .. "...")
        later(PACE, prepare)
        return
    end
    Q.busyTicks = 0
    -- The recipient, again.
    if not s.custom then
        if s.to == ns.charKey or MB.IsSelf(nil, s.name) then
            s.status, s.error = "skipped", "That's this character."
            advance()
            return
        end
        if not MB.CanMail(s.to) then
            s.status, s.error = "failed", "Can't mail " .. (s.name or "?") .. " from here."
            stopSending("error", s.error)
            return
        end
    elseif MB.IsSelf(nil, s.name) then
        s.status, s.error = "skipped", "That's this character."
        advance()
        return
    end
    local atts, notes = revalidate(s)
    if #atts == 0 and (s.money or 0) <= 0 and not s.custom then
        s.status, s.error = "skipped", "Nothing left to send: your bags changed."
        advance()
        return
    end
    -- Postage and your reserve.
    local postage = MB.Postage(#atts)
    local money = ns.try(GetMoney) or 0
    if money - postage - (s.money or 0) < MB.Reserve() then
        if s.gold then
            s.money = max(0, money - MB.Reserve() - postage - remainingPostage(Q.i))
            if s.money <= 0 and #atts == 0 then
                s.status, s.error = "skipped",
                    MB.Reserve() > 0 and "No spare gold left above your reserve." or "No spare gold left after postage."
                advance()
                return
            end
            notes[#notes + 1] = "gold lowered to " .. plain(s.money)
                .. (MB.Reserve() > 0 and " to keep your reserve" or " to cover postage")
        else
            s.status = "planned"
            stopSending("error", "Postage for " .. shipLabel(s) .. " " .. shortWords() .. ". Nothing was sent.")
            return
        end
    end
    s.changed = #notes > 0 and table.concat(notes, "; ") or nil
    s.atts = atts
    local sums, list = {}, {}
    for _, a in ipairs(atts) do
        if not sums[a.id] then
            sums[a.id] = { id = a.id, qty = 0 }
            list[#list + 1] = sums[a.id]
        end
        sums[a.id].qty = sums[a.id].qty + a.count
    end
    s.items = list
    s.status = "preparing"
    setStatus("working", "Putting " .. plural(#atts, "stack") .. " on " .. shipLabel(s) .. "...")
    clearAttachments()
    sendShowing(true)
    for j, a in ipairs(atts) do
        call(C_Container.PickupContainerItem, a.bag, a.slot)
        call(ClickSendMailItemButton, j)
        if CursorHasItem and ns.try(CursorHasItem) then
            pcall(ClearCursor)
            s.status, s.error = "failed", "The game wouldn't attach " .. ns.ItemName(a.id) .. "."
            stopSending("error", s.error .. " Nothing was sent.")
            return
        end
    end
    -- The attachments show up a moment later; check them before asking for
    -- the click.
    local tries = 0
    local function check()
        if Q.mode ~= "send" or currentShip() ~= s or s.status ~= "preparing" then
            return
        end
        if attachmentsMatch(atts) then
            s.postage = ns.try(GetSendMailPrice) or postage
            s.status = "ready"
            setStatus("ready", (Q.auto and "Auto-send: " or "") .. "Ready: " .. shipLabel(s) .. ", postage "
                .. plain(s.postage) .. (s.changed and (". Your bags changed: " .. s.changed) or "")
                .. ". Press Send (one click per mail).")
            return
        end
        tries = tries + 1
        if tries > 8 then
            s.status, s.error = "failed", "The attachments didn't match what was planned."
            stopSending("error", s.error .. " Nothing was sent.")
            return
        end
        later(PACE, check)
    end
    later(0.2, check)
end

local function sendResolved(s, status, text)
    local op = Q.op
    Q.op = nil
    s.status = status
    s.result = text
    sendShowing(false)
    if status ~= "sent" then
        clearAttachments()
    end
    ns.Fire("MAIL_SENT", s, status)
    if status == "sent" then
        setStatus("working", "Sent " .. shipLabel(s) .. ".")
        if Q.mode == "send" then
            advance()
        end
    elseif status == "unclear" then
        MB.unclear[#MB.unclear + 1] = s
        stopSending("unclear", text)
    else
        stopSending("error", text)
    end
    return op
end

-- What the bags and gold say about a mail whose answer never came.
local function reconcile(op)
    local s = op.ship
    if type(HasSendMailItem) == "function" and #s.atts > 0 then
        local still = true
        for j = 1, #s.atts do
            if not ns.try(HasSendMailItem, j) then
                still = false
            end
        end
        if still and attachmentsMatch(s.atts) then
            return "failed", "No answer from the server and the items are still on the mail, so it wasn't sent."
                .. " They're back in your bags."
        end
    end
    local gone = true
    for _, it in ipairs(s.items) do
        if bagCount(it.id) > (op.bags[it.id] or 0) - it.qty then
            gone = false
        end
    end
    local paid = (ns.try(GetMoney) or 0) <= op.money - s.postage - (s.money or 0)
    if gone and paid then
        return "unclear", "No answer from the server, but the items left your bags and the postage was paid, so "
            .. shipLabel(s) .. " most likely went out. Check " .. (s.name or "their") .. "'s mailbox before sending these again."
    end
    return "unclear", "No answer from the server about " .. shipLabel(s) .. ". Check your bags and "
        .. (s.name or "their") .. "'s mailbox before sending again. Nothing was resent."
end

-- The Send button. Must run straight from a click.
function MB.SendNext()
    local s = currentShip()
    if Q.mode ~= "send" or not s then
        return false, "Nothing is ready to send."
    end
    if Q.op then
        return false, "Still waiting for the server."
    end
    if s.status ~= "ready" then
        return false, s.status == "preparing" and "Still putting the attachments on." or "Not ready yet."
    end
    if not MB.open then
        stopSending("error", "The mailbox closed. Nothing more was sent.")
        return false
    end
    if serverBusy() then
        return false, "The server is still busy. Try again in a moment."
    end
    -- Last checks, right before it goes.
    if not attachmentsMatch(s.atts) then
        s.status, s.error = "failed", "The attachments changed before sending."
        stopSending("error", s.error .. " Nothing was sent.")
        return false
    end
    if s.custom then
        if MB.IsSelf(nil, s.name) then
            stopSending("error", "That's you. Nothing was sent.")
            return false
        end
    elseif s.to == ns.charKey or not MB.CanMail(s.to) then
        stopSending("error", "Can't mail " .. (s.name or "?") .. " from here. Nothing was sent.")
        return false
    end
    local postage = ns.try(GetSendMailPrice) or s.postage
    local money = ns.try(GetMoney) or 0
    if s.gold then
        s.money = min(s.money or 0, max(0, money - MB.Reserve() - postage - remainingPostage(Q.i)))
    end
    if money - postage - (s.money or 0) < MB.Reserve() then
        stopSending("error", "Sending " .. shortWords() .. ". Nothing was sent.")
        return false
    end
    s.postage = postage
    s.status = "sending"
    local op = { kind = "send", ship = s, at = GetTime(), money = money, bags = {} }
    for _, it in ipairs(s.items) do
        op.bags[it.id] = bagCount(it.id)
    end
    Q.op = op
    if type(SetSendMailCOD) == "function" then
        call(SetSendMailCOD, 0)
    end
    if type(SetSendMailMoney) == "function" then
        call(SetSendMailMoney, 0)
        if (s.money or 0) > 0 then
            call(SetSendMailMoney, s.money)
        end
    end
    if (s.cod or 0) > 0 and type(SetSendMailCOD) == "function" then
        call(SetSendMailCOD, s.cod)
    end
    local ok = call(SendMail, s.name, s.subject or "", s.body or "")
    if not ok then
        sendResolved(s, "failed", "The game wouldn't send it. Nothing was sent.")
        return false
    end
    setStatus("waiting", "Sent " .. shipLabel(s) .. " - waiting for the server to confirm...")
    later(SEND_TIMEOUT, function()
        local function timeout()
            if Q.op ~= op then
                return
            end
            if op.confirm and GetTime() - op.at < CONFIRM_TIMEOUT then
                later(2, timeout)
                return
            end
            local status, text = reconcile(op)
            sendResolved(s, status, text)
        end
        timeout()
    end)
    return true
end

-- Starts sending a plan's mails, one click each.
function MB.StartSend(plan, auto)
    if not MB.open then
        return false, "Open a mailbox first."
    end
    if Q.mode then
        return false, Q.mode == "collect" and "Busy collecting mail. Wait for it to finish." or "Already sending."
    end
    if not plan or plan.problem then
        return false, plan and plan.problem or "Nothing to send."
    end
    if #plan.ships == 0 then
        return false, "Nothing to send."
    end
    Q.mode, Q.ships, Q.i, Q.op, Q.stopAfter, Q.auto, Q.busyTicks = "send", plan.ships, 1, nil, nil, auto, 0
    Q.plan = plan
    newToken()
    prepare()
    return true
end

-- Stops after whatever the server is working on right now.
function MB.Stop()
    if not Q.mode then
        return
    end
    if Q.op then
        Q.stopAfter, Q.stopWhy = true, "Stopped. Nothing more was sent."
        setStatus("waiting", "Stopping once the server answers...")
        return
    end
    if Q.mode == "send" then
        stopSending("idle", "Stopped. Nothing more was sent.")
    else
        finishCollect("idle", collectSummary() .. " Stopped.")
    end
end

-- Carries on with the next mail that hasn't gone yet, after you've checked.
function MB.Resume()
    if Q.mode or not Q.ships then
        return false
    end
    for j, s in ipairs(Q.ships) do
        if s.status == "planned" then
            Q.mode, Q.i, Q.op, Q.stopAfter, Q.busyTicks = "send", j, nil, nil, 0
            newToken()
            prepare()
            return true
        end
    end
    return false
end

function MB.CanResume()
    if Q.mode or not Q.ships then
        return false
    end
    for _, s in ipairs(Q.ships) do
        if s.status == "planned" then
            return true
        end
    end
    return false
end

function MB.ClearShipments()
    if Q.mode then
        return false
    end
    Q.ships, Q.i, Q.plan = nil, 0, nil
    MB.status = { kind = "idle", text = "" }
    ns.Fire("MAIL")
    return true
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

ns.On("MAIL_SHOW", function()
    MB.open = true
    MB.inboxState = "loading"
    MB.inbox = {}
    MB.exclude = {}
    if not Q.mode then
        Q.ships, Q.i, Q.plan = nil, 0, nil
        MB.status = { kind = "idle", text = "" }
    end
    ns.Fire("MAIL_OPENED")
    -- If the inbox was already loaded this session, there may be no update.
    C_Timer.After(1.5, ns.Guard("mail-inbox", function()
        if MB.open and MB.inboxState == "loading" then
            readInbox()
            MB.inboxState = "ready"
            ns.Fire("MAIL")
        end
    end))
    if O().mailAuto then
        C_Timer.After(0.8, ns.Guard("mail-auto", function()
            if not MB.open or Q.mode then
                return
            end
            local plan = MB.PlanRules()
            if #plan.ships > 0 and not plan.problem then
                MB.autoPlan = plan
                MB.StartSend(plan, true)
                ns.Fire("MAIL_AUTO", plan)
            else
                setStatus("idle", "Auto-send: nothing matches your rules right now.")
            end
        end))
    elseif O().mailPrompt ~= false then
        -- Not auto-sending: if your rules have mail to send, offer it.
        C_Timer.After(0.8, ns.Guard("mail-prompt", function()
            if not MB.open or Q.mode then
                return
            end
            local any = false
            for _, r in ipairs(MB.Rules()) do
                if r.on then
                    any = true
                    break
                end
            end
            if not any then
                return
            end
            local plan = MB.PlanRules()
            if #plan.ships > 0 and not plan.problem then
                ns.Fire("MAIL_PROMPT", plan)
            end
        end))
    end
end)

ns.On("MAIL_CLOSED", function()
    if not MB.open then
        return
    end
    MB.open = false
    MB.inboxState = "closed"
    if Q.mode == "collect" then
        if Q.op then
            Q.stopAfter, Q.stopWhy = true, "The mailbox closed, so collecting stopped."
        else
            finishCollect("error", collectSummary() .. " The mailbox closed, so collecting stopped.")
        end
    elseif Q.mode == "send" then
        if Q.op then
            -- It's already with the server: keep listening for the answer.
            Q.stopAfter, Q.stopWhy = true, "The mailbox closed. Nothing more was sent."
        else
            stopSending("error", "The mailbox closed. Nothing more was sent.")
        end
    end
    ns.Fire("MAIL_CLOSED_UI")
end)

ns.On("MAIL_INBOX_UPDATE", function()
    if not MB.open then
        return
    end
    readInbox()
    MB.inboxState = "ready"
    checkTake()
    ns.Later("mail-ui", 0.1, function() ns.Fire("MAIL") end)
end)

ns.On("MAIL_SUCCESS", function()
    checkTake()
end)

ns.On("MAIL_SEND_SUCCESS", function()
    local op = Q.op
    if op and op.kind == "send" then
        if op.ambiguous then
            sendResolved(op.ship, "unclear", "Another mail went out at the same time, so it's not certain which one the"
                .. " server confirmed. Check " .. (op.ship.name or "their") .. "'s mailbox.")
        else
            sendResolved(op.ship, "sent")
        end
        return
    end
    -- A late answer for a mail we'd given up on.
    for i, s in ipairs(MB.unclear) do
        if s.status == "unclear" then
            s.status, s.result = "sent", "Confirmed late by the server."
            table.remove(MB.unclear, i)
            setStatus("done", "The server confirmed the earlier mail to " .. (s.name or "?") .. " after all.")
            return
        end
    end
end)

ns.On("UI_ERROR_MESSAGE", function(_, message)
    if MB.open and type(message) == "string" then
        MB.lastError = { text = message, at = GetTime() }
    end
end)

local function recentError()
    local e = MB.lastError
    if e and GetTime() - e.at < 3 then
        return e.text
    end
    return nil
end

ns.On("MAIL_FAILED", function(itemID)
    local op = Q.op
    if not op then
        return
    end
    if op.kind == "send" then
        sendResolved(op.ship, "failed", "The server refused " .. shipLabel(op.ship)
            .. (recentError() and (": " .. recentError()) or "") .. ". Nothing was sent; the items are back in your bags.")
    elseif op.what then
        takeResolved(op, false, recentError() or (itemID and ns.ItemName(itemID)) or "refused")
    end
end)

-- The game's own "are you sure?" for sending to or taking gold from someone
-- it doesn't know. The player answers it; we just wait longer.
ns.On("SECURE_TRANSFER_CONFIRM_SEND_MAIL", function()
    local op = Q.op
    if op and op.kind == "send" then
        op.confirm, op.at = true, GetTime()
        setStatus("confirm", "The game is asking you to confirm " .. shipLabel(op.ship) .. ". Answer its dialog.")
    end
end)

ns.On("SECURE_TRANSFER_CONFIRM_TAKE_MAIL_MONEY", function()
    local op = Q.op
    if op and op.what == "money" then
        op.confirm, op.at = true, GetTime()
        setStatus("confirm", "The game is asking you to confirm taking this gold. Answer its dialog.")
    end
end)

ns.On("SECURE_TRANSFER_CANCEL", function()
    local op = Q.op
    if not op then
        return
    end
    if op.kind == "send" then
        sendResolved(op.ship, "cancelled", "You cancelled " .. shipLabel(op.ship) .. " in the game's dialog. Nothing was sent.")
    elseif op.what then
        takeResolved(op, false, "cancelled")
    end
end)

-- A refundable item: the game asks before it can be mailed. Don't let that
-- dialog decide for us.
ns.On("MAIL_LOCK_SEND_ITEMS", function(slot)
    local s = currentShip()
    if Q.mode == "send" and s and (s.status == "preparing" or s.status == "ready") then
        if StaticPopup_Hide then
            pcall(StaticPopup_Hide, "CONFIRM_MAIL_ITEM_UNREFUNDABLE")
        end
        local a = type(slot) == "number" and s.atts[slot]
        s.status, s.error = "failed", (a and ns.ItemName(a.id) or "An item") .. " can still be refunded, so the game asks first."
        stopSending("error", s.error .. " Send it from the game's mailbox if you're sure. Nothing was sent.")
    end
end)

for _, ev in ipairs({ "PLAYER_MONEY", "BAG_UPDATE_DELAYED" }) do
    ns.On(ev, function()
        if Q.op and Q.op.what then
            checkTake()
        end
        if MB.open and ev == "BAG_UPDATE_DELAYED" then
            ns.Later("mail-bags", 0.3, function() ns.Fire("MAIL_BAGS") end)
        end
    end)
end

-- Mail actions that didn't come from us (the game's mailbox, another addon)
-- while we're busy: finish what's with the server, then stop.
local function outside(what)
    return function()
        if MB.selfCall then
            return
        end
        MB.outsideAt = GetTime()
        if not Q.mode then
            return
        end
        local why = "Another mail action (" .. what .. ") ran while Forever Gold was busy, so it stopped. Nothing more was sent or taken."
        if Q.op then
            if Q.op.kind == "send" and what == "SendMail" then
                Q.op.ambiguous = true
            end
            Q.stopAfter, Q.stopWhy = true, why
        elseif Q.mode == "send" then
            stopSending("error", why)
        else
            finishCollect("error", collectSummary() .. " " .. why)
        end
    end
end

ns.Listen("READY", function()
    if type(hooksecurefunc) ~= "function" then
        return
    end
    for _, name in ipairs({ "TakeInboxItem", "TakeInboxMoney", "AutoLootMailItem", "SendMail", "ReturnInboxItem",
        "DeleteInboxItem" }) do
        if type(_G[name]) == "function" then
            pcall(hooksecurefunc, name, outside(name))
        end
    end
end)

-- Leaving our window for the game's: fine unless something is with the
-- server right now. A mail waiting for your click gets its items back.
function MB.HandOver()
    if Q.op then
        return false, "Wait until the server answers."
    end
    if Q.mode == "send" then
        stopSending("idle", "Switched to the game's mailbox. Nothing more was sent.")
    elseif Q.mode == "collect" then
        finishCollect("idle", collectSummary() .. " Switched to the game's mailbox.")
    end
    return true
end
