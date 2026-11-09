-- One activity feed, no duplicates (2026-11-09).
--
-- The Dashboard's Recent Activity and the floating sidebar now read
-- activity_log (the table the Activity page already uses), so every new
-- kind - PvP, duels, deaths, dungeon clears, AH, epic items, reputation -
-- shows up everywhere. Safe to run more than once.

-- 1. Badge art in the sidebar/dashboard: which achievement a row is about
alter table public.activity_log add column if not exists achievement_kind text;
alter table public.activity_log add column if not exists achievement_tier text;

-- Fill them in for rows already mirrored from activity_events
update public.activity_log l
set achievement_kind = e.achievement_kind, achievement_tier = e.achievement_tier
from public.activity_events e
where l.achievement_kind is null
  and e.achievement_kind is not null
  and e.user_id = l.user_id
  and e.character_id is not distinct from l.character_id
  and e.message = l.label;

-- 2. Remove any duplicates already there (keeps the earliest of each)
delete from public.activity_log a
using public.activity_log b
where a.user_id = b.user_id
  and a.character_id is not distinct from b.character_id
  and a.kind = b.kind
  and a.label = b.label
  and (a.created_at, a.id) > (b.created_at, b.id)
  and (
    a.created_at = b.created_at
    or a.kind in ('level_up', 'achievement_earned', 'account_achievement_earned',
                  'legacy_completed', 'character_created', 'boss_first_kill', 'reputation_milestone')
  );

-- The old table too, so nothing reading it shows the 4 doubled rows
delete from public.activity_events a
using public.activity_events b
where a.user_id = b.user_id
  and a.character_id is not distinct from b.character_id
  and a.kind = b.kind
  and a.message = b.message
  and (a.created_at, a.id) > (b.created_at, b.id)
  and a.kind in ('level_up', 'achievement_earned', 'legacy_completed', 'character_created');

-- 3. The database itself refuses a second copy from now on.
-- Things that only ever happen once (a level, a badge, a first clear) can't
-- repeat their text at all...
create unique index if not exists activity_log_once_unique
  on public.activity_log (user_id, coalesce(character_id, '00000000-0000-0000-0000-000000000000'::uuid), kind, label)
  where kind in ('level_up', 'achievement_earned', 'account_achievement_earned',
                 'legacy_completed', 'character_created', 'boss_first_kill', 'reputation_milestone');

-- ...and everything else (kills, duels, loot) can't repeat at the same moment
create unique index if not exists activity_log_moment_unique
  on public.activity_log (user_id, coalesce(character_id, '00000000-0000-0000-0000-000000000000'::uuid), kind, label, created_at);

-- 4. Live updates for the sidebar
do $$
begin
  alter publication supabase_realtime add table public.activity_log;
exception when duplicate_object then null;
end $$;
