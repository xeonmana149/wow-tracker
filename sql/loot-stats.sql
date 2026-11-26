-- Lifetime gathering and loot counters (2026-11-26). The tracker addon
-- (1.9.20+) counts herbs, ore, skins and fish gathered, chests and bag
-- containers opened, and green-or-better loot by where it dropped; each
-- sync stores the latest here. Shape: lib/lootStats.ts. characters is
-- already readable by everyone, and only the sync route (service role)
-- writes it.
alter table public.characters add column if not exists loot_stats jsonb;
