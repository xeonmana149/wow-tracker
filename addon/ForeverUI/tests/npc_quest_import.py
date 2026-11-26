"""Regression checks for the retained OneForAll quest-pin import format."""
import importlib.util
from pathlib import Path

root = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('npc_quest_import', root / 'scripts/import-npc-quest-relations.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

pins = module.parse_quest_pins('''
  [1411] = [[
!42.1,68.3,Gornek
788|2|1|0|H||0|||||Cutting Teeth
~42.1,68.3;42.2,68.3
789|3|1|0|H||0|||||Sting of the Scorpid
?42.1,68.3,788/789,Gornek
!bad,0,Not an NPC
990|2|1|0|H||0|||||Must not be attached
  ]],
''')
assert len(pins) == 2
assert pins[0]['mapID'] == 1411 and pins[0]['quests'] == [(788, 'Cutting Teeth'), (789, 'Sting of the Scorpid')]
assert pins[1]['role'] == 'turnins' and pins[1]['quests'] == [(788, None), (789, None)]
print('Quest pin parser handles start, turn-in, paths and malformed positions')
