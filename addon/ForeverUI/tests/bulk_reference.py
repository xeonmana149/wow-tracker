"""Check bulk provenance, field precedence, and completeness against its inputs."""
import json, re
from pathlib import Path
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[3];base=root/'addon/ForeverUI/data/forever-kb'
read=lambda name:json.loads((base/(name+'.json')).read_text(encoding='utf8'))
tracker=read('tracker-verified')['items']; kb={r['id']:r for r in read('items')}; report=read('import-report')
lua=LuaRuntime(unpack_returned_tuples=True); run=lua.eval('function(s,ns) local f,e=loadstring(s); assert(f,e); return f("ForeverUI",ns) end'); ns=lua.table();run((root/'addon/ForeverUI/BulkReferenceData.lua').read_text(encoding='utf8'),ns)
data=ns.BulkReferenceData; items={row.id:row for row in data['items'].values()}
availability=json.loads((root/'addon/ForeverUI/data/wowhead-availability.json').read_text(encoding='utf8'))['records']
assert len(availability)==report['wowheadUnavailable']+report['wowheadUnconfirmed']+report['wowheadContested']
for evidence in availability:
 out=data.availability[evidence['id']]
 assert out.status==evidence['status'] and out.checkedAt==evidence['checkedAt'] and out.url==evidence['url']
 if evidence['status']=='contested': assert out.reason==evidence['reason']
assert data.availability[215369].status=='contested' and data.availability[215369].reason
assert data.availability[211857].status=='unavailable' and data.availability[220446].status=='unconfirmed'
# Evidence is keyed to individual variants; the deprecated Thunderfury must not
# cause the real, tracker-observed legendary to be filtered out.
assert data.availability[17802].status=='unavailable' and data.availability[19019] is None
for item_id in (217270, 7949, 18584, 21588, 18355, 18023):
 assert data.availability[item_id].status=='unavailable' and item_id in items
assert any(row['id']==19019 and row.get('verified') for row in tracker)
assert data.availability[289294].status=='unavailable' and data.availability[19019] is None
underworld=items[1980]
assert any('Stamina:' in conflict and 'Wowhead 12' in conflict for conflict in underworld.conflicts.values())
# Intellect is absent from the baseline; it must not be reported as zero.
assert not any('Intellect:' in conflict for conflict in underworld.conflicts.values())
assert any('Stamina:' in conflict and 'Wowhead 7' in conflict for conflict in items[1204].conflicts.values())
assert len(items)==report['bulkItems'] and len(data.quests)==report['bulkQuests'] and len(data.npcs)==report['bulkNpcs']
quests={row.id:row for row in data.quests.values()}
assert quests[6].classic and len(quests[6].classic.objectives)>0 and len(quests[6].classic.rewards)>0
assert sum(bool(row.classic) for row in quests.values())>4000
assert len(data.classicEdges)==report['classicExtraLinks'] and len(data.classicEdges)>2000
classic = [tuple(edge.values()) for edge in data.classicEdges.values()]
assert len({(e[0],e[2],e[3]) for e in classic})==len(classic)
assert all(e[0] in items and e[1]=='n' and e[3] in ('drop','vendor') and len(e)==4 for e in classic)
base_sources={(r['item_id'],r['kind']) for r in read('item_sources')}
assert all((e[0],e[3]) not in base_sources for e in classic)
assert len(data.objectEdges)==report['objectLinks'] and len(data.containerEdges)==report['containerLinks'] and len(data.craftEdges)==report['craftLinks']
objects={row.id for row in data.objects.values()}
assert all(edge[1] in items and edge[2] in objects for edge in data.objectEdges.values())
assert all(edge[1] in items and edge[2] in items and edge[1]!=edge[2] for edge in data.containerEdges.values())
assert all(edge[1] in items and edge[2]>0 and edge[3] for edge in data.craftEdges.values())
assert items[117].itemClass == 'Consumable' and items[117].slot == 'Non-equippable'
assert items[117].sourceTypes and items[117].sourceSummary, 'catalogue must retain acquisition and category metadata'
assert all(row['id'] in items for row in tracker if row.get('verified') and not row.get('hidden'))
checked=0
for live in tracker:
 if live['id'] not in kb or not live.get('tooltip'):continue
 raw=kb[live['id']]; out=items[live['id']]
 observed=next((int(m.group(1)) for line in live['tooltip'] if isinstance(line,str) and (m:=re.search(r'\bItem Level\s+(\d+)',line,re.I))),None)
 if observed is not None:
  assert out.itemLevel==observed; checked+=1
 elif raw.get('item_level') is not None:
  assert out.itemLevel==raw['item_level']
 if live.get('required_level_scanned'): assert out.requiredLevel==(live.get('required_level') or 0)
assert checked>0
assert all(edge[1] in items for edge in data.edges.values())
print('Bulk records, all verified tracker discoveries and observed field precedence verified;',checked,'tooltip item levels checked')

