"""Check the read-only encyclopedia adapter against the installed OneForAll data."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

base = Path(r"C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/OneForAll")
lua = LuaRuntime(unpack_returned_tuples=True)
run = lua.eval('function(s,n,t) local f,e=loadstring(s,n); if not f then error(e) end; return f("OneForAll",t) end')
data = lua.table()
files = ["Data.lua", "ExtraData.lua", "ProfessionData.lua"]
files += ["Data/Professions/" + p + ".lua" for p in
          ("Alchemy", "Tailoring", "Blacksmithing", "Leatherworking", "Engineering", "Enchanting", "Cooking", "FirstAid")]
files += ["DungeonRegistry.lua", "Data/Dungeons/HallofThanes.lua", "Data/Dungeons/WailingCaverns.lua", "Data/Dungeons/OnyxiasLair.lua", "Data/Dungeons/BarrowDeeps.lua", "Data/Dungeons/HyjalSummit.lua", "DungeonData.lua", "Data/BossInfo.lua", "Data/DungeonDropChance.lua", "Data/DungeonLoadscreens.lua", "Data/HunterPets.lua", "Data/HunterPetTames.lua", "Data/Armory.lua", "Data/Enchants.lua"]
for name in files:
    run((base / name).read_text(encoding="utf-8"), name, data)
lua.globals().OneForAll = data
ns = lua.table()
run(Path("addon/ForeverUI/Encyclopedia.lua").read_text(encoding="utf-8"), "Encyclopedia.lua", ns)
encyclopedia = ns.Encyclopedia
encyclopedia.RefreshData(encyclopedia)
for category, search in (("Dungeons", "Wailing Caverns"), ("Pets", "Cat"),
                         ("Camping", "Anvil"), ("Armory", "Armor"), ("Reputations", "Argent Dawn")):
    matches = encyclopedia.Find(encyclopedia, category, search)
    assert len(matches), (category, search)
    print(category, search, len(matches))

campfire = encyclopedia.Find(encyclopedia, "Professions", "Journeyman Campfire Kit")[1]
assert any(link.kind == "boss" and link.name == "Lord Serpentis" for link in campfire.links.values())
boss = next(link for link in campfire.links.values() if link.kind == "boss" and link.name == "Lord Serpentis")
assert any(link.kind == "dungeon" and link.name == "Wailing Caverns" for link in boss.links.values())
print("Journeyman Campfire Kit -> Lord Serpentis -> Wailing Caverns")
camp_objects = [e for e in encyclopedia.Find(encyclopedia, "Camping", "Sharpening Wheel").values() if e.kind == "campObject"]
assert camp_objects and camp_objects[0].extra == "Blacksmithing" and camp_objects[0].data.effect
books = [e for e in encyclopedia.Find(encyclopedia, "Library Books", "Dalaran Digest").values() if e.kind == "book"]
assert books and books[0].data.set == "starter" and books[0].data.zone == "Silverpine Forest"
print("Camping effects and Library Books reference records resolve")
assert any(o.n == "Enchant Bracer - Inferior Stamina" and o.e == 41 for o in data.ENCHANT_OPTIONS.values())
assert data.ENCHANTS[41][1] == "+2 Stamina"
print("Enchant options and effect descriptions resolve")
enchant = next(o for o in data.ENCHANT_OPTIONS.values() if o.s == 7443)
enchant_details = encyclopedia.EnchantDetails(enchant)
enchant_sources = list(enchant_details.sources.values())
assert any("Kithas" in src and "Orgrimmar" in src for src in enchant_sources)
assert any("Carnivous the Breaker" in src for src in enchant_sources)
print("Enchant links to recorded vendors and mob drops")

wolf = encyclopedia.Find(encyclopedia, "Pets", "Prairie Stalker")[1]
assert wolf.kind == "tame" and wolf.data.family == "Wolf" and wolf.data.zone == "Mulgore"
assert any(link.kind == "petRank" and link.name == "Bite — Rank 1" for link in wolf.links.values())
assert any(link.kind == "family" and link.name == "Wolf" for link in wolf.links.values())
assert len(encyclopedia.Find(encyclopedia, "Pets", "Mulgore")) > 1
print("Prairie Stalker -> Wolf and Bite rank 1; zone search works")
humar = encyclopedia.Find(encyclopedia, "Pets", "Humar the Pridelord")[1]
assert humar.kind == "tame" and "Rare spawn" in humar.data.note
assert any(link.kind == "family" and link.name == "Cat" for link in humar.links.values())
assert len(encyclopedia.Find(encyclopedia, "Pets", "Duskbat")) > 1
print("Rare details and extra tame records are present")
wc = next(e for e in encyclopedia.Find(encyclopedia, "Dungeons", "Wailing Caverns").values() if e.kind == "dungeon")
onyxia = next(e for e in encyclopedia.Find(encyclopedia, "Dungeons", "Onyxia's Lair").values() if e.kind == "dungeon")
barrow = next(e for e in encyclopedia.Find(encyclopedia, "Dungeons", "Barrow Deeps").values() if e.kind == "dungeon")
hyjal = next(e for e in encyclopedia.Find(encyclopedia, "Dungeons", "Hyjal Summit").values() if e.kind == "dungeon")
assert (barrow.data.size, hyjal.data.size, onyxia.data.size) == (10, 20, 40)
print("Raid sizes resolve from OneForAll: 10, 20 and 40 players")
assert encyclopedia.DungeonArt(wc.data, 70, 32)[0] == 131882
assert encyclopedia.DungeonArt(onyxia.data, 70, 32)[0] == 131863
print("Dungeon and raid loading-screen artwork resolves")
hall = next(e for e in encyclopedia.Find(encyclopedia, "Dungeons", "Hall of Thanes").values() if e.kind == "dungeon")
bosses = [e for e in hall.links.values() if e.kind == "boss"]
assert bosses[0].name == "Faldrim Anvilmar" and bosses[0].data.displayID
assert data.BOSS_LEVELS[bosses[0].data.npcID] == "16" and data.BOSS_TYPES[bosses[0].data.npcID] == "Undead"
chance = data.GetDropChance(hall.name, bosses[0].name, 270227)
assert chance and chance[0] == 34
print("Hall of Thanes boss order, portrait ID, level, type and drop data resolve")
