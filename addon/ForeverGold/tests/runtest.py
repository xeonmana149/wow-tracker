"""Loads Forever Gold into a mock WoW client (Lua 5.1) and drives it end to end."""
import sys, os, re
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = sys.argv[1]

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(HERE, "mock.lua"), encoding="utf-8").read())

toc = open(os.path.join(ADDON, "ForeverGold.toc"), encoding="utf-8").read()
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
lua.execute("NS = {}")
load = lua.eval("""function(src, name)
    local f, err = loadstring(src, "@" .. name)
    if not f then error(err) end
    f("ForeverGold", NS)
end""")
for f in files:
    load(open(os.path.join(ADDON, f), encoding="utf-8").read(), f)
print("loaded:", ", ".join(files))

script = open(os.path.join(HERE, "scenario.lua"), encoding="utf-8").read()
lua.execute(script)
