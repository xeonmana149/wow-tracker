"""Regression tests for QuestieDB's baked NPC location reference importer."""
import base64
import importlib.util
from pathlib import Path

root = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('questie_npc_import', root / 'scripts/import-questie-npc-data.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

value = 'oQ6BgvtARQeuFHrhSPtAURUeuFHrhQ=='
assert module.decode(value) == {14: [[42.06, 68.33]]}
assert module.get({'x': '~2~', 'x-1': value[:16], 'x-2': value[16:]}, 'x') == {14: [[42.06, 68.33]]}
assert module.decode(base64.b64encode(bytes.fromhex('f93e00')).decode()) == 1.5
maps = module.area_maps('''
ZoneDB.private.areaIdToUiMapId = [[return { [14] = 1411,
 [2257] = 499, }]]
ZoneDB.private.areaIdToUiMapIdOverride = [[return { [2257] = 0,
 [14] = 1411, }]]
'''.replace('{ [', '{\n ['))
assert maps[14] == 1411 and maps[2257] == 0
print('Questie NPC importer handles CBOR, chunks and suppressed map overrides')
