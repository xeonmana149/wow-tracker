"""Loads Forever UI into Forever Gold's mock WoW client (Lua 5.1) and checks it.

    python runtest.py ..        (from addon/ForeverUI/tests)
"""
import sys, os
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, ".."))
MOCK = os.path.join(HERE, "..", "..", "ForeverGold", "tests", "mock.lua")

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(MOCK, encoding="utf-8").read())
lua.execute(open(os.path.join(HERE, "client.lua"), encoding="utf-8").read())

toc = open(os.path.join(ADDON, "ForeverUI.toc"), encoding="utf-8").read()
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
lua.execute("NS = {}")
load = lua.eval("""function(src, name)
    local f, err = loadstring(src, "@" .. name)
    if not f then error(err) end
    f("ForeverUI", NS)
end""")
for f in files:
    load(open(os.path.join(ADDON, f), encoding="utf-8").read(), f)
print("loaded:", ", ".join(files))

lua.execute(open(os.path.join(HERE, "scenario.lua"), encoding="utf-8").read())
