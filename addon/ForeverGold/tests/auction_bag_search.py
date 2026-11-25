"""Exercise auction searches through real Forever Gold bag button hooks."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute((root / 'tests/mock.lua').read_text(encoding='utf8'))
lua.execute('NS = {}')
load = lua.eval('function(src, name) local f,e=loadstring(src,"@"..name); assert(f,e); f("ForeverGold",NS) end')
for name in (root / 'ForeverGold.toc').read_text(encoding='utf8').splitlines():
    name = name.strip()
    if name and not name.startswith('#'):
        load((root / name).read_text(encoding='utf8'), name)
lua.execute('''
local M, ns = MOCK, NS
M.fire("ADDON_LOADED", "ForeverGold"); M.fire("PLAYER_LOGIN"); M.advance(5)
ns.db.opts.fastScan = false
M.fire("AUCTION_HOUSE_SHOW"); M.advance(1)
ns.scan.active = false
ns.BagUI.Open(); M.advance(1)
local button
for _, frame in ipairs(M.frames) do
    if frame:IsShown() and frame.fgCell and frame.fgCell.live and frame.fgCell.id == 2770 then button = frame; break end
end
assert(button, "live Copper Ore bag button missing")
local a, f = ns.AuctionUI, ForeverGoldAuctionFrame
a.BUY.category = {name="Weapons", top=1, filters={{classID=2}}}
local before = M.lastBrowse
M.shift = true; button:Click("LeftButton"); M.shift = false
assert(f.browse.search:GetText() == "Copper Ore", "shift click must insert item name")
assert(a.BUY.category == nil and before == M.lastBrowse, "shift click must clear category without searching")
ns.scan.active = false; f.browse.go:Click(); M.advance(5)
assert(M.lastBrowse and M.lastBrowse.searchString == "Copper Ore" and M.lastBrowse.itemClassFilters == nil, "search must cover every category: " .. tostring(a.BUY.message) .. " / " .. tostring(M.lastBrowse and M.lastBrowse.searchString))
M.shift = true; button:Click("RightButton"); M.shift = false
assert(ns.BagUI.IsMarked(2770), "shift-right banker marking remains available")
''')
print('Live bag shift-click, unrestricted search and banker shortcut passed')
