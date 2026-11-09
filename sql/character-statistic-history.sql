-- Statistic history (2026-11-09, "can we attach times and dates to
-- statistics?"). One row each time a character's statistic changes value,
-- with when it changed. character_statistics keeps only the current value;
-- this keeps every value it has had since history started.
--
-- changed_at is the exact time the addon noticed the change in-game
-- (addon 1.9.5+ checks every few minutes and right after a boss dies), or
-- the sync time when the addon didn't report one.
--
-- A character's first sync after this exists writes one row per stat with
-- is_baseline = true: the starting values, not changes - when those values
-- were reached isn't known.
--
-- Written only by the sync route (service role); readable by everyone,
-- like character_statistics.

create table if not exists public.character_statistic_history (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  user_id uuid,
  stat_id integer not null,
  category text,
  name text,
  value text,
  previous_value text,
  is_baseline boolean not null default false,
  changed_at timestamptz not null default now()
);

create index if not exists character_statistic_history_char_stat_idx
  on public.character_statistic_history (character_id, stat_id, changed_at desc);
create index if not exists character_statistic_history_char_time_idx
  on public.character_statistic_history (character_id, changed_at desc);

alter table public.character_statistic_history enable row level security;

drop policy if exists "Statistic history is viewable by everyone" on public.character_statistic_history;
create policy "Statistic history is viewable by everyone"
  on public.character_statistic_history for select
  using (true);
