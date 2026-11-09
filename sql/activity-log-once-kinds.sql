-- Gold milestones and repeat dungeon/raid clears post once each (2026-11-09).
-- Adds them to the "only ever once" rule from sql/activity-log-dedupe.sql.
-- Safe to run more than once.

delete from public.activity_log a
using public.activity_log b
where a.user_id = b.user_id
  and a.character_id is not distinct from b.character_id
  and a.kind = b.kind
  and a.label = b.label
  and (a.created_at, a.id) > (b.created_at, b.id)
  and a.kind in ('gold_milestone', 'boss_clear');

drop index if exists public.activity_log_once_unique;
create unique index activity_log_once_unique
  on public.activity_log (user_id, coalesce(character_id, '00000000-0000-0000-0000-000000000000'::uuid), kind, label)
  where kind in ('level_up', 'achievement_earned', 'account_achievement_earned',
                 'legacy_completed', 'character_created', 'boss_first_kill', 'reputation_milestone',
                 'gold_milestone', 'boss_clear');
