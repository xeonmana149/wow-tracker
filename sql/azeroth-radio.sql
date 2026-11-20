-- Azeroth Radio: shared listening stations (2026-11-19).
--
-- Only adds new radio_* tables and functions; nothing existing changes.
-- Everything is written through the website's /api/radio routes, which use
-- the service role and call the functions below. RLS is on with no
-- policies, so the anon/authenticated keys can't read or write any of it
-- directly, and the functions are only executable by service_role.
--
-- How a station "keeps running" on serverless hosting: there's no timer.
-- Each station has one state row (current track, when it started, how long
-- it is). Every read or write first calls radio_tick(), which - under a row
-- lock - moves the station on past any tracks that have finished since,
-- back to back, as if it had been playing all along. So a station keeps its
-- schedule with nobody listening, and nothing depends on any one listener.
--
-- Audio is never stored or relayed: rows hold only provider track ids,
-- titles, durations and links. Each listener plays the track through the
-- provider's own player.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists public.radio_stations (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  name text not null check (char_length(name) between 1 and 80),
  description text check (char_length(description) <= 300),
  mode text not null default 'requests' check (mode in ('requests', 'curated_only')),
  requests_paused boolean not null default false,
  skip_min_votes integer not null default 2 check (skip_min_votes between 1 and 100),
  skip_ratio numeric not null default 0.5 check (skip_ratio > 0 and skip_ratio <= 1),
  created_by uuid,
  created_at timestamptz not null default now()
);
-- Shuffle (added 2026-11-20): the station's own playlist plays in a random
-- order, every song once before any repeats, reshuffled each time round.
alter table public.radio_stations add column if not exists shuffle boolean not null default true;

create table if not exists public.radio_station_roles (
  station_id uuid not null references public.radio_stations(id) on delete cascade,
  user_id uuid not null,
  role text not null check (role in ('host', 'moderator')),
  primary key (station_id, user_id)
);

-- Tracks any station has seen: provider id plus the display details the
-- provider's own player reports. duration_ms is null until known.
create table if not exists public.radio_tracks (
  id bigint generated always as identity primary key,
  -- Songs a station can play: SoundCloud tracks, through SoundCloud's own
  -- embedded player. Links to other services (YouTube, Spotify, ...) only
  -- ever become suggestions. ('youtube' is still allowed by this check only
  -- so older rows load; radio_upsert_track refuses new ones.)
  provider text not null check (provider in ('soundcloud', 'youtube')),
  provider_id text not null,
  check (case provider when 'soundcloud' then provider_id ~ '^[0-9]{1,20}$'
                       when 'youtube' then provider_id ~ '^[A-Za-z0-9_-]{11}$' end),
  title text check (char_length(title) <= 300),
  artist text check (char_length(artist) <= 200),
  duration_ms integer check (duration_ms between 1000 and 10800000),
  permalink_url text check (char_length(permalink_url) <= 500),
  artwork_url text check (char_length(artwork_url) <= 500),
  updated_at timestamptz not null default now(),
  unique (provider, provider_id)
);

-- A station's curated playlist: the approved catalog and the fallback order.
create table if not exists public.radio_station_tracks (
  station_id uuid not null references public.radio_stations(id) on delete cascade,
  track_id bigint not null references public.radio_tracks(id) on delete cascade,
  position integer not null,
  active boolean not null default true,
  primary key (station_id, track_id)
);
create index if not exists radio_station_tracks_order on public.radio_station_tracks (station_id, position);

-- Requests. 'suggestion' rows are links from services we can't play: shown
-- as labelled suggestions, never queued for playback.
create table if not exists public.radio_queue (
  id bigint generated always as identity primary key,
  station_id uuid not null references public.radio_stations(id) on delete cascade,
  track_id bigint references public.radio_tracks(id) on delete cascade,
  suggestion_url text check (char_length(suggestion_url) <= 500),
  requested_by uuid not null,
  requested_at timestamptz not null default clock_timestamp(),
  status text not null check (status in ('pending', 'needs_approval', 'playing', 'played', 'removed', 'suggestion')),
  decided_by uuid,
  updated_at timestamptz not null default now(),
  check (case when status = 'suggestion' then track_id is null else track_id is not null or status = 'removed' end)
);
-- One waiting request per account per station.
create unique index if not exists radio_queue_one_per_user
  on public.radio_queue (station_id, requested_by) where status in ('pending', 'needs_approval');
-- No duplicate waiting tracks.
create unique index if not exists radio_queue_no_dupes
  on public.radio_queue (station_id, track_id) where status in ('pending', 'needs_approval');
create index if not exists radio_queue_station_status on public.radio_queue (station_id, status);

create table if not exists public.radio_queue_votes (
  queue_id bigint not null references public.radio_queue(id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (queue_id, user_id)
);

-- The authoritative timeline. instance_id changes every time a track starts
-- (even the same track again), so votes and reports are tied to one play.
create table if not exists public.radio_station_state (
  station_id uuid primary key references public.radio_stations(id) on delete cascade,
  track_id bigint references public.radio_tracks(id) on delete set null,
  queue_id bigint references public.radio_queue(id) on delete set null,
  requested_by uuid,
  instance_id uuid not null default gen_random_uuid(),
  started_at timestamptz not null default clock_timestamp(),
  duration_ms integer,
  curated_position integer not null default -1,
  queue_rev bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.radio_skip_votes (
  station_id uuid not null references public.radio_stations(id) on delete cascade,
  instance_id uuid not null,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (station_id, instance_id, user_id)
);

-- Who's listening: one row per signed-in account per station, refreshed by
-- a heartbeat. Accounts, not tabs or windows.
create table if not exists public.radio_presence (
  station_id uuid not null references public.radio_stations(id) on delete cascade,
  user_id uuid not null,
  last_seen timestamptz not null default now(),
  primary key (station_id, user_id)
);

-- Desktop-app sign-in for the radio only. Separate from user_sync_tokens:
-- a radio token can't upload characters, and a sync token can't use the
-- radio. Only SHA-256 hashes are stored.
create table if not exists public.radio_device_tokens (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  label text check (char_length(label) <= 60),
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
create table if not exists public.radio_link_codes (
  code_hash text primary key check (code_hash ~ '^[0-9a-f]{64}$'),
  user_id uuid not null,
  expires_at timestamptz not null,
  used_at timestamptz
);

create table if not exists public.radio_problem_reports (
  id bigint generated always as identity primary key,
  station_id uuid not null references public.radio_stations(id) on delete cascade,
  instance_id uuid,
  track_id bigint,
  user_id uuid not null,
  kind text not null check (kind in ('unavailable', 'preview', 'blocked', 'network', 'autoplay', 'sync', 'other')),
  detail text check (char_length(detail) <= 300),
  created_at timestamptz not null default now()
);

create table if not exists public.radio_rate_events (
  user_id uuid not null,
  action text not null,
  at timestamptz not null default clock_timestamp()
);
create index if not exists radio_rate_events_lookup on public.radio_rate_events (user_id, action, at);
create index if not exists radio_rate_events_at on public.radio_rate_events (at);

alter table public.radio_stations enable row level security;
alter table public.radio_station_roles enable row level security;
alter table public.radio_tracks enable row level security;
alter table public.radio_station_tracks enable row level security;
alter table public.radio_queue enable row level security;
alter table public.radio_queue_votes enable row level security;
alter table public.radio_station_state enable row level security;
alter table public.radio_skip_votes enable row level security;
alter table public.radio_presence enable row level security;
alter table public.radio_device_tokens enable row level security;
alter table public.radio_link_codes enable row level security;
alter table public.radio_problem_reports enable row level security;
alter table public.radio_rate_events enable row level security;

-- ---------------------------------------------------------------------------
-- Settings shared by the functions
-- ---------------------------------------------------------------------------
-- A listener counts as active for this long after their last heartbeat.
create or replace function public.radio_active_window() returns interval
  language sql immutable as $$ select interval '45 seconds' $$;
-- Used for a track whose length isn't known yet, until a listener's player
-- reports it.
create or replace function public.radio_provisional_ms() returns integer
  language sql immutable as $$ select 600000 $$;

create or replace function public.radio_fail(p_code text, p_message text) returns void
  language plpgsql as $$
begin
  raise exception '%', p_message using errcode = 'P0001', hint = p_code;
end $$;

-- Sliding-window rate limit. Records the event when it's allowed.
create or replace function public.radio_rate(p_user uuid, p_action text, p_max integer, p_window interval)
returns void language plpgsql as $$
declare n integer;
begin
  select count(*) into n from public.radio_rate_events
    where user_id = p_user and action = p_action and at > clock_timestamp() - p_window;
  if n >= p_max then
    perform public.radio_fail('rate_limited', 'Slow down a little - try again in a moment.');
  end if;
  insert into public.radio_rate_events (user_id, action) values (p_user, p_action);
end $$;

create or replace function public.radio_role(p_station uuid, p_user uuid) returns text
  language sql stable as $$
  select role from public.radio_station_roles where station_id = p_station and user_id = p_user
$$;

create or replace function public.radio_require_mod(p_station uuid, p_user uuid) returns void
  language plpgsql as $$
begin
  if p_user is null or public.radio_role(p_station, p_user) is null then
    perform public.radio_fail('forbidden', 'Only this station''s host and moderators can do that.');
  end if;
end $$;

create or replace function public.radio_station_id(p_slug text) returns uuid
  language plpgsql stable as $$
declare sid uuid;
begin
  select id into sid from public.radio_stations where slug = p_slug;
  if sid is null then perform public.radio_fail('not_found', 'That station doesn''t exist.'); end if;
  return sid;
end $$;

-- Votes still count only while their voter is an active listener.
create or replace function public.radio_skip_counts(p_station uuid, p_instance uuid,
  out votes integer, out required integer, out listeners integer)
language plpgsql stable as $$
declare st public.radio_stations;
begin
  select * into st from public.radio_stations where id = p_station;
  select count(*) into listeners from public.radio_presence
    where station_id = p_station and last_seen > clock_timestamp() - public.radio_active_window();
  select count(*) into votes from public.radio_skip_votes v
    join public.radio_presence p on p.station_id = v.station_id and p.user_id = v.user_id
    where v.station_id = p_station and v.instance_id = p_instance
      and p.last_seen > clock_timestamp() - public.radio_active_window();
  required := greatest(st.skip_min_votes, ceil(listeners * st.skip_ratio)::integer);
end $$;

-- ---------------------------------------------------------------------------
-- Shuffle
-- ---------------------------------------------------------------------------
-- The songs still to come this time round (after curated_position), in a new
-- random order. Songs already played this round keep their places.
create or replace function public.radio_shuffle_rest(p_station uuid) returns void
language plpgsql as $$
declare cp integer;
begin
  select coalesce(curated_position, -1) into cp from public.radio_station_state where station_id = p_station;
  cp := coalesce(cp, -1);
  update public.radio_station_tracks t set position = cp + r.rn
    from (select x.track_id, (row_number() over (order by random()))::integer as rn
          from public.radio_station_tracks x
          where x.station_id = p_station and x.active and x.position > cp) r
    where t.station_id = p_station and t.track_id = r.track_id;
end $$;

-- A new round: every song in a new random order, with the one that just
-- played last so it never plays twice in a row.
create or replace function public.radio_shuffle_all(p_station uuid, p_last bigint) returns void
language plpgsql as $$
begin
  update public.radio_station_tracks t set position = r.rn - 1
    from (select x.track_id, (row_number() over (order by (x.track_id is not distinct from p_last), random()))::integer as rn
          from public.radio_station_tracks x
          where x.station_id = p_station and x.active) r
    where t.station_id = p_station and t.track_id = r.track_id;
end $$;

-- ---------------------------------------------------------------------------
-- The timeline
-- ---------------------------------------------------------------------------
-- What plays next: in request mode the most-voted waiting request (earliest
-- request breaks ties), otherwise the next track of the curated playlist,
-- wrapping round. Returns nulls when the station has nothing at all.
create or replace function public.radio_pick_next(p_station uuid, p_after_position integer, p_current_track bigint,
  out queue_id bigint, out track_id bigint, out requested_by uuid, out curated_position integer)
language plpgsql as $$
declare st public.radio_stations; n integer;
begin
  select * into st from public.radio_stations where id = p_station;
  curated_position := p_after_position;
  if st.mode = 'requests' then
    select q.id, q.track_id, q.requested_by into queue_id, track_id, requested_by
      from public.radio_queue q
      where q.station_id = p_station and q.status = 'pending'
      order by (select count(*) from public.radio_queue_votes v where v.queue_id = q.id) desc, q.requested_at asc, q.id asc
      limit 1;
    if queue_id is not null then return; end if;
  end if;
  select count(*) into n from public.radio_station_tracks where station_id = p_station and active;
  if n = 0 then return; end if;
  select t.track_id, t.position into track_id, curated_position from public.radio_station_tracks t
    where t.station_id = p_station and t.active and t.position > p_after_position
      and (n = 1 or t.track_id is distinct from p_current_track)
    order by t.position limit 1;
  if track_id is null then
    -- End of the playlist: round again (reshuffled first when shuffle is on).
    if st.shuffle and n > 1 then perform public.radio_shuffle_all(p_station, p_current_track); end if;
    select t.track_id, t.position into track_id, curated_position from public.radio_station_tracks t
      where t.station_id = p_station and t.active and (n = 1 or t.track_id is distinct from p_current_track)
      order by t.position limit 1;
  end if;
end $$;

-- Starts the next track at p_start. Caller holds the state row lock.
create or replace function public.radio_advance(p_station uuid, p_start timestamptz) returns void
language plpgsql as $$
declare s public.radio_station_state; nx record;
begin
  select * into s from public.radio_station_state where station_id = p_station;
  if s.queue_id is not null then
    update public.radio_queue set status = 'played', updated_at = now() where id = s.queue_id and status = 'playing';
  end if;
  select * into nx from public.radio_pick_next(p_station, s.curated_position, s.track_id);
  if nx.queue_id is not null then
    update public.radio_queue set status = 'playing', updated_at = now() where id = nx.queue_id;
  end if;
  update public.radio_station_state set
    track_id = nx.track_id,
    queue_id = nx.queue_id,
    requested_by = nx.requested_by,
    curated_position = coalesce(nx.curated_position, s.curated_position),
    instance_id = gen_random_uuid(),
    started_at = p_start,
    duration_ms = (select duration_ms from public.radio_tracks where id = nx.track_id),
    queue_rev = s.queue_rev + 1,
    updated_at = now()
  where station_id = p_station;
  delete from public.radio_skip_votes where station_id = p_station and instance_id = s.instance_id;
end $$;

-- Brings a station up to date. Locks its state row, so concurrent calls for
-- the same station run one after another.
create or replace function public.radio_tick(p_station uuid) returns void
language plpgsql as $$
declare s public.radio_station_state; ends timestamptz; i integer := 0; c record;
begin
  insert into public.radio_station_state (station_id) values (p_station) on conflict do nothing;
  select * into s from public.radio_station_state where station_id = p_station for update;
  if s.track_id is null then
    -- Idle station (empty, or everything was removed): start whatever's
    -- available now. Nothing available -> stays idle (and unchanged).
    if exists (select 1 from public.radio_station_tracks where station_id = p_station and active)
       or exists (select 1 from public.radio_queue q join public.radio_stations st on st.id = q.station_id
                  where q.station_id = p_station and q.status = 'pending' and st.mode = 'requests') then
      perform public.radio_advance(p_station, clock_timestamp());
    end if;
    return;
  end if;
  loop
    select * into s from public.radio_station_state where station_id = p_station;
    exit when s.track_id is null;
    ends := s.started_at + make_interval(secs => coalesce(s.duration_ms, public.radio_provisional_ms()) / 1000.0);
    if clock_timestamp() < ends then
      -- Still playing: is there a winning skip vote (listeners may have left)?
      select * into c from public.radio_skip_counts(p_station, s.instance_id);
      exit when c.votes = 0 or c.votes < c.required;
      perform public.radio_advance(p_station, clock_timestamp());
      exit;
    end if;
    i := i + 1;
    if i > 60 then
      -- Long-idle station: don't replay hours of history, just start now.
      perform public.radio_advance(p_station, clock_timestamp());
      exit;
    end if;
    perform public.radio_advance(p_station, ends);
  end loop;
  -- Housekeeping, cheap enough to do here.
  delete from public.radio_presence where station_id = p_station and last_seen < clock_timestamp() - interval '10 minutes';
  if random() < 0.02 then
    delete from public.radio_rate_events where at < clock_timestamp() - interval '1 hour';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Reading a station
-- ---------------------------------------------------------------------------
create or replace function public.radio_track_json(p_track bigint) returns jsonb
  language sql stable as $$
  select case when t.id is null then null else jsonb_build_object(
    'id', t.id, 'provider', t.provider, 'providerId', t.provider_id, 'title', t.title, 'artist', t.artist,
    'durationMs', t.duration_ms, 'permalinkUrl', t.permalink_url, 'artworkUrl', t.artwork_url) end
  from (select p_track as x) a left join public.radio_tracks t on t.id = a.x
$$;

create or replace function public.radio_display_name(p_user uuid) returns text
  language sql stable as $$
  select coalesce((select nullif(trim(display_name), '') from public.profiles where id = p_user), 'A listener')
$$;

create or replace function public.radio_get_state(p_slug text, p_user uuid default null) returns jsonb
language plpgsql as $$
declare sid uuid; st public.radio_stations; s public.radio_station_state; c record; role text; q jsonb; mine jsonb;
begin
  sid := public.radio_station_id(p_slug);
  perform public.radio_tick(sid);
  select * into st from public.radio_stations where id = sid;
  select * into s from public.radio_station_state where station_id = sid;
  select * into c from public.radio_skip_counts(sid, s.instance_id);
  role := case when p_user is null then null else public.radio_role(sid, p_user) end;

  select coalesce(jsonb_agg(e order by (e->>'votes')::int desc, e->>'requestedAt', (e->>'id')::bigint), '[]'::jsonb) into q from (
    select jsonb_build_object(
      'id', qq.id, 'status', qq.status, 'track', public.radio_track_json(qq.track_id),
      'suggestionUrl', qq.suggestion_url,
      'requestedBy', public.radio_display_name(qq.requested_by),
      'mine', qq.requested_by = p_user,
      'requestedAt', to_char(qq.requested_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'votes', (select count(*) from public.radio_queue_votes v where v.queue_id = qq.id),
      'myVote', exists (select 1 from public.radio_queue_votes v where v.queue_id = qq.id and v.user_id = p_user)
    ) as e
    from public.radio_queue qq
    where qq.station_id = sid
      and (qq.status = 'pending'
        or (qq.status in ('needs_approval', 'suggestion') and (role is not null or qq.requested_by = p_user)))
  ) x;

  return jsonb_build_object(
    'station', jsonb_build_object('id', st.id, 'slug', st.slug, 'name', st.name, 'description', st.description,
      'mode', st.mode, 'requestsPaused', st.requests_paused, 'skipMinVotes', st.skip_min_votes, 'skipRatio', st.skip_ratio,
      'shuffle', st.shuffle),
    'serverNow', floor(extract(epoch from clock_timestamp()) * 1000),
    'now', jsonb_build_object(
      'instanceId', s.instance_id,
      'track', public.radio_track_json(s.track_id),
      'startedAt', floor(extract(epoch from s.started_at) * 1000),
      'durationMs', s.duration_ms,
      'provisional', s.track_id is not null and s.duration_ms is null,
      'requestedBy', case when s.requested_by is null then null else public.radio_display_name(s.requested_by) end,
      'source', case when s.track_id is null then 'idle' when s.queue_id is null then 'playlist' else 'request' end),
    'queueRev', s.queue_rev,
    'listeners', c.listeners,
    'skip', jsonb_build_object('votes', c.votes, 'required', c.required,
      'mine', p_user is not null and exists (select 1 from public.radio_skip_votes v where v.station_id = sid and v.instance_id = s.instance_id and v.user_id = p_user)),
    'queue', q,
    'me', case when p_user is null then null else jsonb_build_object('role', role, 'name', public.radio_display_name(p_user),
      'listening', exists (select 1 from public.radio_presence p where p.station_id = sid and p.user_id = p_user
        and p.last_seen > clock_timestamp() - public.radio_active_window())) end,
    'catalogSize', (select count(*) from public.radio_station_tracks where station_id = sid and active)
  );
end $$;

create or replace function public.radio_list_stations() returns jsonb
language plpgsql as $$
declare r record; res jsonb := '[]'::jsonb; s public.radio_station_state;
begin
  for r in select * from public.radio_stations order by created_at loop
    perform public.radio_tick(r.id);
    select * into s from public.radio_station_state where station_id = r.id;
    res := res || jsonb_build_object('slug', r.slug, 'name', r.name, 'description', r.description,
      'listeners', (select count(*) from public.radio_presence p where p.station_id = r.id and p.last_seen > clock_timestamp() - public.radio_active_window()),
      'track', public.radio_track_json(s.track_id));
  end loop;
  return res;
end $$;

-- ---------------------------------------------------------------------------
-- Listener actions
-- ---------------------------------------------------------------------------
create or replace function public.radio_heartbeat(p_slug text, p_user uuid, p_listening boolean) returns jsonb
language plpgsql as $$
declare sid uuid;
begin
  sid := public.radio_station_id(p_slug);
  perform public.radio_rate(p_user, 'heartbeat', 30, interval '1 minute');
  if p_listening then
    -- One station at a time per account.
    delete from public.radio_presence where user_id = p_user and station_id <> sid;
    insert into public.radio_presence (station_id, user_id, last_seen) values (sid, p_user, clock_timestamp())
      on conflict (station_id, user_id) do update set last_seen = excluded.last_seen;
  else
    delete from public.radio_presence where station_id = sid and user_id = p_user;
  end if;
  return public.radio_get_state(p_slug, p_user);
end $$;

create or replace function public.radio_vote_skip(p_slug text, p_user uuid, p_instance uuid, p_vote boolean) returns jsonb
language plpgsql as $$
declare sid uuid; s public.radio_station_state; c record;
begin
  sid := public.radio_station_id(p_slug);
  perform public.radio_rate(p_user, 'skip', 20, interval '1 minute');
  perform public.radio_tick(sid);
  select * into s from public.radio_station_state where station_id = sid for update;
  if s.track_id is null or s.instance_id is distinct from p_instance then
    perform public.radio_fail('stale', 'That song has already changed.');
  end if;
  if not exists (select 1 from public.radio_presence where station_id = sid and user_id = p_user
      and last_seen > clock_timestamp() - public.radio_active_window()) then
    perform public.radio_fail('not_listening', 'Join the station to vote.');
  end if;
  if p_vote then
    insert into public.radio_skip_votes (station_id, instance_id, user_id) values (sid, p_instance, p_user) on conflict do nothing;
  else
    delete from public.radio_skip_votes where station_id = sid and instance_id = p_instance and user_id = p_user;
  end if;
  select * into c from public.radio_skip_counts(sid, p_instance);
  if c.votes >= c.required then
    perform public.radio_advance(sid, clock_timestamp());
  end if;
  return public.radio_get_state(p_slug, p_user);
end $$;

-- p_track: an already-upserted radio_tracks id (the API checks the link
-- with the provider first), or null with p_suggestion_url for an
-- unsupported service.
create or replace function public.radio_request(p_slug text, p_user uuid, p_track bigint, p_suggestion_url text) returns jsonb
language plpgsql as $$
declare sid uuid; st public.radio_stations; s public.radio_station_state; in_catalog boolean; v_status text;
begin
  sid := public.radio_station_id(p_slug);
  select * into st from public.radio_stations where id = sid;
  perform public.radio_rate(p_user, 'request', 6, interval '10 minutes');
  if p_track is null then
    if p_suggestion_url is null then perform public.radio_fail('bad_request', 'Nothing to request.'); end if;
    insert into public.radio_queue (station_id, track_id, suggestion_url, requested_by, status)
      values (sid, null, p_suggestion_url, p_user, 'suggestion');
    return public.radio_get_state(p_slug, p_user);
  end if;
  if st.mode = 'curated_only' then perform public.radio_fail('curated_only', 'This station only plays its own playlist right now.'); end if;
  if st.requests_paused then perform public.radio_fail('paused', 'Requests are paused on this station.'); end if;
  perform public.radio_tick(sid);
  select * into s from public.radio_station_state where station_id = sid for update;
  if s.track_id = p_track then perform public.radio_fail('playing', 'That song is playing right now.'); end if;
  if exists (select 1 from public.radio_queue where station_id = sid and requested_by = p_user and status in ('pending', 'needs_approval')) then
    perform public.radio_fail('one_request', 'You already have a request waiting on this station. Withdraw it to request something else.');
  end if;
  if exists (select 1 from public.radio_queue where station_id = sid and track_id = p_track and status in ('pending', 'needs_approval')) then
    perform public.radio_fail('duplicate', 'That song is already in the queue - vote for it instead.');
  end if;
  in_catalog := exists (select 1 from public.radio_station_tracks where station_id = sid and track_id = p_track and active);
  v_status := case when in_catalog then 'pending' else 'needs_approval' end;
  begin
    insert into public.radio_queue (station_id, track_id, requested_by, status) values (sid, p_track, p_user, v_status);
  exception when unique_violation then
    -- Lost a race with a simultaneous request: same answers as above.
    perform public.radio_fail('duplicate', 'That song is already in the queue, or you already have a request waiting.');
  end;
  update public.radio_station_state set queue_rev = queue_rev + 1 where station_id = sid;
  return public.radio_get_state(p_slug, p_user);
end $$;

create or replace function public.radio_withdraw(p_slug text, p_user uuid, p_queue bigint) returns jsonb
language plpgsql as $$
declare sid uuid;
begin
  sid := public.radio_station_id(p_slug);
  update public.radio_queue set status = 'removed', decided_by = p_user, updated_at = now()
    where id = p_queue and station_id = sid and requested_by = p_user and status in ('pending', 'needs_approval', 'suggestion');
  if not found then perform public.radio_fail('not_found', 'That request isn''t waiting any more.'); end if;
  update public.radio_station_state set queue_rev = queue_rev + 1 where station_id = sid;
  return public.radio_get_state(p_slug, p_user);
end $$;

create or replace function public.radio_vote_queue(p_slug text, p_user uuid, p_queue bigint, p_vote boolean) returns jsonb
language plpgsql as $$
declare sid uuid;
begin
  sid := public.radio_station_id(p_slug);
  perform public.radio_rate(p_user, 'vote', 40, interval '1 minute');
  if not exists (select 1 from public.radio_queue where id = p_queue and station_id = sid and status = 'pending') then
    perform public.radio_fail('not_found', 'That song isn''t in the queue any more.');
  end if;
  if p_vote then
    insert into public.radio_queue_votes (queue_id, user_id) values (p_queue, p_user) on conflict do nothing;
  else
    delete from public.radio_queue_votes where queue_id = p_queue and user_id = p_user;
  end if;
  update public.radio_station_state set queue_rev = queue_rev + 1 where station_id = sid;
  return public.radio_get_state(p_slug, p_user);
end $$;

-- A listener's player reports a track's real length the first time it's
-- unknown. Only fills a gap; never changes a known length.
create or replace function public.radio_report_duration(p_slug text, p_user uuid, p_instance uuid, p_duration integer) returns void
language plpgsql as $$
declare sid uuid; s public.radio_station_state;
begin
  sid := public.radio_station_id(p_slug);
  if p_duration is null or p_duration < 5000 or p_duration > 10800000 then return; end if;
  perform public.radio_rate(p_user, 'duration', 20, interval '10 minutes');
  select * into s from public.radio_station_state where station_id = sid for update;
  if s.instance_id is distinct from p_instance or s.duration_ms is not null or s.track_id is null then return; end if;
  update public.radio_tracks set duration_ms = p_duration, updated_at = now() where id = s.track_id and duration_ms is null;
  update public.radio_station_state set duration_ms = p_duration, updated_at = now() where station_id = sid;
end $$;

create or replace function public.radio_report_problem(p_slug text, p_user uuid, p_instance uuid, p_kind text, p_detail text) returns void
language plpgsql as $$
declare sid uuid; s public.radio_station_state;
begin
  sid := public.radio_station_id(p_slug);
  perform public.radio_rate(p_user, 'report', 10, interval '10 minutes');
  select * into s from public.radio_station_state where station_id = sid;
  insert into public.radio_problem_reports (station_id, instance_id, track_id, user_id, kind, detail)
    values (sid, p_instance, case when s.instance_id = p_instance then s.track_id end, p_user, p_kind, left(p_detail, 300));
end $$;

-- ---------------------------------------------------------------------------
-- Host and moderator actions
-- ---------------------------------------------------------------------------
-- Adds songs to the end of a station's playlist, in order, skipping any that
-- are already on it (and repeats within the list). A song that was removed
-- earlier comes back at the end. Returns how many were added.
create or replace function public.radio_catalog_add(p_station uuid, p_ids bigint[]) returns integer
language plpgsql as $$
declare pos integer; tid bigint; added integer := 0;
begin
  select coalesce(max(position), -1) into pos from public.radio_station_tracks where station_id = p_station;
  foreach tid in array coalesce(p_ids, '{}') loop
    continue when exists (select 1 from public.radio_station_tracks where station_id = p_station and track_id = tid and active);
    pos := pos + 1;
    insert into public.radio_station_tracks (station_id, track_id, position, active) values (p_station, tid, pos, true)
      on conflict (station_id, track_id) do update set active = true, position = excluded.position;
    added := added + 1;
  end loop;
  -- Shuffled stations mix new songs in among the ones still to come.
  if added > 0 and (select shuffle from public.radio_stations where id = p_station) then perform public.radio_shuffle_rest(p_station); end if;
  return added;
end $$;

create or replace function public.radio_moderate(p_slug text, p_user uuid, p_action text, p_args jsonb) returns jsonb
language plpgsql as $$
declare sid uuid; qid bigint; n integer; pos integer; t jsonb; tid bigint; ids bigint[];
begin
  sid := public.radio_station_id(p_slug);
  perform public.radio_require_mod(sid, p_user);
  perform public.radio_rate(p_user, 'moderate', 60, interval '1 minute');
  perform public.radio_tick(sid);
  perform 1 from public.radio_station_state where station_id = sid for update;
  qid := nullif(p_args->>'queueId', '')::bigint;
  case p_action
    when 'approve' then
      update public.radio_queue set status = 'pending', decided_by = p_user, updated_at = now()
        where id = qid and station_id = sid and status = 'needs_approval';
      if not found then perform public.radio_fail('not_found', 'That request isn''t waiting for approval.'); end if;
    when 'remove' then
      update public.radio_queue set status = 'removed', decided_by = p_user, updated_at = now()
        where id = qid and station_id = sid and status in ('pending', 'needs_approval', 'suggestion');
      if not found then perform public.radio_fail('not_found', 'That request isn''t waiting any more.'); end if;
    when 'advance' then
      perform public.radio_advance(sid, clock_timestamp());
    when 'set_mode' then
      update public.radio_stations set mode = p_args->>'mode' where id = sid and p_args->>'mode' in ('requests', 'curated_only');
      if not found then perform public.radio_fail('bad_request', 'Unknown mode.'); end if;
    when 'pause_requests' then
      update public.radio_stations set requests_paused = coalesce((p_args->>'paused')::boolean, true) where id = sid;
    when 'set_skip' then
      update public.radio_stations set
        skip_min_votes = least(100, greatest(1, coalesce((p_args->>'minVotes')::int, skip_min_votes))),
        skip_ratio = least(1, greatest(0.05, coalesce((p_args->>'ratio')::numeric, skip_ratio)))
        where id = sid;
    when 'set_shuffle' then
      update public.radio_stations set shuffle = coalesce((p_args->>'shuffle')::boolean, true) where id = sid;
      if (select shuffle from public.radio_stations where id = sid) then perform public.radio_shuffle_rest(sid); end if;
    when 'catalog_add' then
      -- p_args.trackIds: radio_tracks ids the API has just upserted, in order.
      ids := array(select (x #>> '{}')::bigint from jsonb_array_elements(coalesce(p_args->'trackIds', '[]'::jsonb)) x);
      n := public.radio_catalog_add(sid, ids);
      if n = 0 and cardinality(ids) > 0 then
        perform public.radio_fail('duplicate', case when cardinality(ids) = 1 then 'That song is already in the station''s playlist.'
          else 'Those songs are already in the station''s playlist.' end);
      end if;
    when 'catalog_remove' then
      update public.radio_station_tracks set active = false where station_id = sid and track_id = (p_args->>'trackId')::bigint;
    when 'catalog_clear' then
      update public.radio_station_tracks set active = false where station_id = sid;
    else
      perform public.radio_fail('bad_request', 'Unknown action.');
  end case;
  update public.radio_station_state set queue_rev = queue_rev + 1 where station_id = sid;
  return public.radio_get_state(p_slug, p_user);
end $$;

create or replace function public.radio_catalog(p_slug text, p_user uuid) returns jsonb
language plpgsql as $$
declare sid uuid;
begin
  sid := public.radio_station_id(p_slug);
  return coalesce((select jsonb_agg(public.radio_track_json(track_id) || jsonb_build_object('position', position) order by position)
    from public.radio_station_tracks where station_id = sid and active), '[]'::jsonb);
end $$;

-- Upserts what the provider told us about a track; returns its id.
create or replace function public.radio_upsert_track(p_provider text, p_provider_id text, p_title text, p_artist text,
  p_duration integer, p_permalink text, p_artwork text) returns bigint
language plpgsql as $$
declare tid bigint;
begin
  if p_provider is distinct from 'soundcloud' then
    perform public.radio_fail('unsupported', 'Only SoundCloud songs can play on Azeroth Radio.');
  end if;
  insert into public.radio_tracks (provider, provider_id, title, artist, duration_ms, permalink_url, artwork_url)
    values (p_provider, p_provider_id, left(p_title, 300), left(p_artist, 200),
      case when p_duration between 1000 and 10800000 then p_duration end, left(p_permalink, 500), left(p_artwork, 500))
    on conflict (provider, provider_id) do update set
      title = coalesce(excluded.title, radio_tracks.title),
      artist = coalesce(excluded.artist, radio_tracks.artist),
      duration_ms = coalesce(radio_tracks.duration_ms, excluded.duration_ms),
      permalink_url = coalesce(excluded.permalink_url, radio_tracks.permalink_url),
      artwork_url = coalesce(excluded.artwork_url, radio_tracks.artwork_url),
      updated_at = now()
    returning id into tid;
  return tid;
end $$;

-- A host or moderator imports songs into the station's own playlist, in
-- order (from the official player's track list; the API has checked each
-- entry's fields). Each entry is a SoundCloud track or a YouTube video
-- ("provider", default soundcloud). p_replace switches off everything not in
-- this import.
create or replace function public.radio_import_tracks(p_slug text, p_user uuid, p_tracks jsonb, p_replace boolean) returns jsonb
language plpgsql as $$
declare sid uuid; t jsonb; tid bigint; ids bigint[] := '{}'; n integer := 0; added integer;
begin
  sid := public.radio_station_id(p_slug);
  perform public.radio_require_mod(sid, p_user);
  perform public.radio_rate(p_user, 'import', 10, interval '10 minutes');
  if jsonb_typeof(p_tracks) <> 'array' or jsonb_array_length(p_tracks) > 500 then
    perform public.radio_fail('bad_request', 'Import up to 500 songs at a time.');
  end if;
  for t in select * from jsonb_array_elements(p_tracks) loop
    tid := public.radio_upsert_track(coalesce(nullif(t->>'provider', ''), 'soundcloud'), t->>'id', t->>'title', t->>'artist',
      nullif(t->>'durationMs', '')::integer, t->>'permalink', t->>'artwork');
    ids := ids || tid;
    n := n + 1;
  end loop;
  perform public.radio_tick(sid);
  perform 1 from public.radio_station_state where station_id = sid for update;
  -- Replace: the playlist becomes this list, in this order.
  if p_replace then
    update public.radio_station_tracks set active = false where station_id = sid;
  end if;
  added := public.radio_catalog_add(sid, ids);
  update public.radio_station_state set queue_rev = queue_rev + 1 where station_id = sid;
  -- imported: new to the playlist. duplicates: already on it (or listed twice).
  return jsonb_build_object('imported', added, 'duplicates', n - added, 'state', public.radio_get_state(p_slug, p_user));
end $$;

-- Creating a station is a one-off admin step (SQL editor):
--   select public.radio_create_station('rusty-anvil', 'The Rusty Anvil', 'Tavern tunes', '<your user id>');
create or replace function public.radio_create_station(p_slug text, p_name text, p_description text, p_host uuid) returns uuid
language plpgsql as $$
declare sid uuid;
begin
  insert into public.radio_stations (slug, name, description, created_by) values (p_slug, p_name, p_description, p_host) returning id into sid;
  insert into public.radio_station_roles (station_id, user_id, role) values (sid, p_host, 'host');
  insert into public.radio_station_state (station_id) values (sid);
  return sid;
end $$;

-- ---------------------------------------------------------------------------
-- Desktop sign-in (radio only)
-- ---------------------------------------------------------------------------
create or replace function public.radio_create_link_code(p_user uuid, p_code_hash text) returns void
language plpgsql as $$
begin
  perform public.radio_rate(p_user, 'link_code', 10, interval '10 minutes');
  delete from public.radio_link_codes where user_id = p_user or expires_at < now();
  insert into public.radio_link_codes (code_hash, user_id, expires_at) values (p_code_hash, p_user, now() + interval '10 minutes');
end $$;

create or replace function public.radio_redeem_link_code(p_code_hash text, p_token_hash text, p_label text) returns jsonb
language plpgsql as $$
declare c public.radio_link_codes;
begin
  update public.radio_link_codes set used_at = now()
    where code_hash = p_code_hash and used_at is null and expires_at > now()
    returning * into c;
  if c.user_id is null then perform public.radio_fail('bad_code', 'That code has expired or was already used. Get a new one on the website.'); end if;
  insert into public.radio_device_tokens (user_id, token_hash, label) values (c.user_id, p_token_hash, left(p_label, 60));
  return jsonb_build_object('name', public.radio_display_name(c.user_id));
end $$;

create or replace function public.radio_device_user(p_token_hash text) returns uuid
language plpgsql as $$
declare uid uuid;
begin
  update public.radio_device_tokens set last_used_at = now()
    where token_hash = p_token_hash and revoked_at is null
    returning user_id into uid;
  return uid;
end $$;

create or replace function public.radio_revoke_device(p_token_hash text) returns void
language sql as $$
  update public.radio_device_tokens set revoked_at = now() where token_hash = p_token_hash and revoked_at is null
$$;

create or replace function public.radio_me(p_user uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object('name', public.radio_display_name(p_user),
    'stations', coalesce((select jsonb_agg(jsonb_build_object('slug', s.slug, 'role', r.role))
      from public.radio_station_roles r join public.radio_stations s on s.id = r.station_id where r.user_id = p_user), '[]'::jsonb))
$$;

-- ---------------------------------------------------------------------------
-- SoundCloud only: take any YouTube songs (from before) out of station
-- playlists and the request queues. Safe to run again.
-- ---------------------------------------------------------------------------
update public.radio_station_tracks set active = false
  where active and track_id in (select id from public.radio_tracks where provider <> 'soundcloud');
update public.radio_queue set status = 'removed'
  where status in ('pending', 'needs_approval') and track_id in (select id from public.radio_tracks where provider <> 'soundcloud');

-- ---------------------------------------------------------------------------
-- Only the website's server (service role) may run any of this.
-- ---------------------------------------------------------------------------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'radio\_%' loop
    execute format('revoke all on function %s from public', f.sig);
    if exists (select 1 from pg_roles where rolname = 'anon') then execute format('revoke all on function %s from anon', f.sig); end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then execute format('revoke all on function %s from authenticated', f.sig); end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then execute format('grant execute on function %s to service_role', f.sig); end if;
    -- Pin each function's search_path (Supabase's function_search_path_mutable check).
    execute format('alter function %s set search_path = public, pg_temp', f.sig);
  end loop;
end $$;
