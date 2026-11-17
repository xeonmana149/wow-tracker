# Offline test for Forever Gold

Runs the whole addon against a fake WoW Forever client (fake auction house,
recipes, bags, vendor, map) and checks the advice it produces.

Needs Python with the `lupa` package (it bundles Lua 5.1, the version WoW uses):

    pip install lupa
    python runtest.py ..

- `mock.lua` - the fake client
- `scenario.lua` - the walkthrough and its checks
- `runtest.py` - loads the addon's files in .toc order and runs the scenario

These files are not listed in the .toc, so the game never loads them.
