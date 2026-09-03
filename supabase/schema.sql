-- The Swarm · database
-- Applied to project bocxxdktggogogsrhhss.
--
-- The single most important property of this schema: a client can never read a
-- coordinate. `geog` is blocked by RLS and never appears in a view. The only
-- spatial information a phone receives is a BAND, computed here. Privacy is
-- enforced in Postgres, not in Dart.
-- >>>
create extension if not exists postgis with schema extensions;
-- >>>
create extension if not exists pgcrypto with schema extensions;
-- >>>
-- ---------------------------------------------------------------- profiles
create table if not exists profiles (
  id        uuid primary key references auth.users on delete cascade,
  campus    text not null default 'pilot',
  klass     text not null default 'rogue' check (klass in ('bard','rogue','mage')),
  streak    int  not null default 0,
  shield    int  not null default 1,
  last_night date,
  created   timestamptz not null default now()
);
-- >>>
-- ---------------------------------------------------------------- whispers
create table if not exists whispers (
  id       uuid primary key default gen_random_uuid(),
  author   uuid not null references auth.users on delete cascade,
  body     text not null check (char_length(body) between 1 and 140),
  geog     extensions.geography(point, 4326) not null,   -- never leaves this table
  klass    text not null check (klass in ('bard','rogue','mage')),
  campus   text not null default 'pilot',
  boosts   int  not null default 0,
  bloom    text not null default 'nightly',
  created  timestamptz not null default now(),
  dies_at  timestamptz not null default now() + interval '22 seconds'
);
-- >>>
create index if not exists whispers_geog_idx on whispers using gist (geog);
-- >>>
create index if not exists whispers_alive_idx on whispers (campus, dies_at desc);
-- >>>
-- ------------------------------------------------------------- live presence
create table if not exists beacons (
  user_id  uuid primary key references auth.users on delete cascade,
  geog     extensions.geography(point, 4326) not null,   -- never leaves this table
  campus   text not null default 'pilot',
  frozen   bool not null default false,                  -- the freeze right
  seen     timestamptz not null default now()
);
-- >>>
create index if not exists beacons_geog_idx on beacons using gist (geog);
-- >>>
-- ------------------------------------------------------------------- nights
-- Everything resets at dawn. One row per user per night, and that is the only
-- history the product keeps.
create table if not exists nights (
  user_id   uuid not null references auth.users on delete cascade,
  night     date not null default current_date,
  glow      numeric not null default 34 check (glow between 0 and 100),
  peak_glow numeric not null default 34,
  caught    int not null default 0,
  given     int not null default 0,
  received  int not null default 0,
  closest   numeric,
  rituals   int not null default 0,
  primary key (user_id, night)
);
-- >>>
create table if not exists boosts (
  whisper_id uuid not null references whispers on delete cascade,
  user_id    uuid not null references auth.users on delete cascade,
  created    timestamptz not null default now(),
  primary key (whisper_id, user_id)              -- one boost per person, ever
);
-- >>>
-- ------------------------------------------------------------------- blooms
create table if not exists blooms (
  id       text primary key,
  name     text not null,
  starts   date not null,
  nights   int  not null default 1,
  rule     text not null,
  accent   text not null
);
-- >>>
insert into blooms (id, name, starts, nights, rule, accent) values
  ('nightly','NIGHTLY',        current_date,            365,'Whispers burn 22 seconds. Glow resets at dawn.','#6FF3CE'),
  ('exam','EXAM BLOOM',        current_date + 12,         7,'Whispers burn 3x longer. Everyone gets Still Water.','#FFB347'),
  ('holi','HOLI BLOOM',        current_date + 41,         1,'Every whisper carries pigment. A boost detonates in colour.','#FF4FA3'),
  ('diwali','DIWALI BLOOM',    current_date + 73,         5,'The whole campus glows at maximum. Nobody is dim tonight.','#FFD36B'),
  ('monsoon','MONSOON BLOOM',  current_date + 96,         3,'Rain scatters your ring. Hunters lose you twice as often.','#7FA8FF'),
  ('snow','FIRST SNOW',        current_date + 134,        1,'Everything slows. Whispers drift instead of decaying.','#DCEEFF')
on conflict (id) do nothing;
-- >>>
-- ============================================================== THE BAND RPC
-- The only spatial answer a phone ever gets. Under 10 metres it returns
-- 'mirage' and NOTHING else: no bearing, no coordinate, no narrowing. There is
-- no zoom level, paid tier or class ability that finds a chair.
create or replace function whisper_band(target uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare d numeric;
begin
  select extensions.st_distance(w.geog, b.geog) into d
    from whispers w, beacons b
   where w.id = target and b.user_id = auth.uid();

  if d is null then return 'lost';   end if;
  if d < 10    then return 'mirage'; end if;   -- the floor. permanent.
  if d < 30    then return 'critical'; end if;
  if d < 80    then return 'hot';    end if;
  if d < 180   then return 'warm';   end if;
  return 'cold';
end;
$fn$;
-- >>>
-- What a sonar sweep returns: bodies and bands, never positions.
create or replace function sweep(radius_m numeric default 132)
returns table (id uuid, body text, klass text, boosts int, dies_at timestamptz, band text)
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare me extensions.geography;
begin
  select b.geog into me from beacons b where b.user_id = auth.uid();
  if me is null then return; end if;

  return query
  select w.id, w.body, w.klass, w.boosts, w.dies_at,
         case
           when extensions.st_distance(w.geog, me) < 10  then 'mirage'
           when extensions.st_distance(w.geog, me) < 30  then 'critical'
           when extensions.st_distance(w.geog, me) < 80  then 'hot'
           when extensions.st_distance(w.geog, me) < 180 then 'warm'
           else 'cold'
         end
    from whispers w
   where w.dies_at > now()
     and extensions.st_dwithin(w.geog, me, radius_m);
end;
$fn$;
-- >>>
-- Post a whisper at your own beacon. The client never sends a coordinate.
create or replace function post_whisper(body_in text, bloom_in text default 'nightly')
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare me extensions.geography; k text; life interval; new_id uuid;
begin
  select b.geog into me from beacons b where b.user_id = auth.uid();
  if me is null then raise exception 'no beacon'; end if;
  select p.klass into k from profiles p where p.id = auth.uid();

  life := case bloom_in
            when 'exam' then interval '66 seconds'
            when 'snow' then interval '44 seconds'
            else interval '22 seconds' end;

  insert into whispers (author, body, geog, klass, bloom, dies_at)
  values (auth.uid(), body_in, me, coalesce(k,'rogue'), bloom_in, now() + life)
  returning id into new_id;
  return new_id;
end;
$fn$;
-- >>>
-- Boost once, ever. Brightens them more than it brightens you.
create or replace function boost_whisper(target uuid)
returns int
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare owner uuid;
begin
  insert into boosts (whisper_id, user_id) values (target, auth.uid())
  on conflict do nothing;
  if not found then return -1; end if;

  update whispers set boosts = boosts + 1, dies_at = dies_at + interval '4 seconds'
   where id = target returning author into owner;

  insert into nights (user_id, night, given) values (auth.uid(), current_date, 1)
    on conflict (user_id, night) do update set given = nights.given + 1;
  insert into nights (user_id, night, received) values (owner, current_date, 1)
    on conflict (user_id, night) do update set received = nights.received + 1;

  return 1;
end;
$fn$;
-- >>>
-- Move your beacon. Coordinates come in and are never readable again.
create or replace function beacon_set(lat double precision, lon double precision)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $fn$
begin
  insert into beacons (user_id, geog, seen)
  values (auth.uid(), extensions.st_point(lon, lat)::extensions.geography, now())
  on conflict (user_id) do update set geog = excluded.geog, seen = now();
end;
$fn$;
-- >>>
-- ================================================================= ROW LEVEL
alter table profiles enable row level security;
-- >>>
alter table whispers enable row level security;
-- >>>
alter table beacons  enable row level security;
-- >>>
alter table nights   enable row level security;
-- >>>
alter table boosts   enable row level security;
-- >>>
alter table blooms   enable row level security;
-- >>>
drop policy if exists "own profile" on profiles;
-- >>>
create policy "own profile" on profiles for all
  using (id = auth.uid()) with check (id = auth.uid());
-- >>>
drop policy if exists "beacon is mine alone" on beacons;
-- >>>
-- Nobody, ever, reads anyone else's position directly. Only the RPCs can.
create policy "beacon is mine alone" on beacons for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
-- >>>
drop policy if exists "my nights" on nights;
-- >>>
create policy "my nights" on nights for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
-- >>>
drop policy if exists "insert my own whisper" on whispers;
-- >>>
create policy "insert my own whisper" on whispers for insert
  with check (author = auth.uid());
-- >>>
drop policy if exists "my boosts" on boosts;
-- >>>
create policy "my boosts" on boosts for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
-- >>>
drop policy if exists "blooms are public" on blooms;
-- >>>
create policy "blooms are public" on blooms for select using (true);
-- >>>
-- NOTE: whispers has NO select policy on purpose. Reading happens only through
-- sweep(), which strips geog and author. Direct selects return zero rows.
-- >>>
-- ------------------------------------------------------------ 24h amnesia
-- Deleted, not archived. There is no history to leak, subpoena or scroll.
create or replace function reap()
returns void language sql security definer set search_path = public as $fn$
  delete from whispers where dies_at < now() - interval '1 minute';
  delete from beacons  where seen    < now() - interval '30 minutes';
  delete from nights   where night   < current_date - 1;
$fn$;
