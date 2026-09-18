-- Migration 006 · hunts, the freeze right, and spores
--
-- Weeks 1 and 2 gave the hunt a convincing puppet: `_huntStep` in the Dart
-- engine decides whether a target freezes or runs, and it decides it with a
-- random number. That is fine for one phone and worthless for two, because
-- the person being hunted is not consulted. This migration moves the whole
-- loop into Postgres, where both halves of it are real people.
--
-- The upgrade over 005 is that a hunt tracks a LIVE BEACON, not the fixed
-- point a whisper was dropped at. You are chasing someone who is walking,
-- and they know it.
--
-- Every rule the rest of the schema keeps, this keeps:
--
--   * no coordinate is returned, ever. A hunt answers with the same five
--     band words a whisper answers with, through room_band().
--   * under ten metres the ring bursts and returns 'mirage'. It does not
--     narrow, it does not repeat, and the hunt is deleted rather than
--     continued. There is no purchase, class or bloom that changes this.
--   * being hunted is announced. The quarry is told on the same tick the
--     hunter is told, and standing still dissolves the signal.
--   * neither side ever learns who the other is. `hunts` is unreadable from
--     any client — migration 004 is the reason: RLS is row-level, not
--     column-level, so "read your own hunt row" would hand over the other
--     party's id and two rows would de-anonymise a person.
--   * everything dies. reap() deletes hunts, alerts and spores.
-- >>>
-- -------------------------------------------------------------------- hunts
-- One row per active pursuit. Both ids live here and neither leaves.
create table if not exists hunts (
  id      uuid primary key default gen_random_uuid(),
  hunter  text not null,                        -- swarm_uid(), never returned
  quarry  text not null,                        -- swarm_uid(), never returned
  whisper uuid references whispers(id) on delete set null,
  state   text not null default 'open'
            check (state in ('open','fleeing','frozen','burst','lost')),
  -- When the quarry stopped moving. The signal does not dissolve instantly:
  -- you have to hold still long enough for it to mean something.
  froze_at timestamptz,
  started timestamptz not null default now(),
  dies_at timestamptz not null default now() + interval '4 minutes'
);
-- >>>
-- A hunter has one target, exactly as the engine has one `target`. Partial
-- unique indexes cannot use now(), the same way rooms_one_per_host could not,
-- so the rule lives where it actually holds.
create index if not exists hunts_hunter_idx on hunts (hunter, dies_at desc);
-- >>>
create index if not exists hunts_quarry_idx on hunts (quarry, dies_at desc);
-- >>>
-- ------------------------------------------------------------------- alerts
-- The freeze right, made of rows.
--
-- This table exists instead of letting the quarry read `hunts` because of
-- what it does NOT have: a hunter column. It says "someone is tracking you,
-- and they are this close". It cannot say who, and two of these rows say
-- nothing that one of them does not.
create table if not exists hunt_alerts (
  id      uuid primary key default gen_random_uuid(),
  quarry  text not null,
  hunt    uuid not null references hunts(id) on delete cascade,
  band    text not null,
  created timestamptz not null default now(),
  dies_at timestamptz not null default now() + interval '5 minutes'
);
-- >>>
create index if not exists hunt_alerts_quarry_idx on hunt_alerts (quarry, created desc);
-- >>>
-- ------------------------------------------------------------------- spores
-- A mark left where you stood, which blooms once you have walked away from it.
-- It is the one thing in the app that points at a place rather than a person,
-- which is exactly why it is allowed to: by the time anyone can see it, its
-- author is somewhere else.
create table if not exists spores (
  id      uuid primary key default gen_random_uuid(),
  author  text not null,                        -- never returned
  geog    extensions.geography(point, 4326) not null,  -- never leaves this table
  campus  text not null default 'pilot',
  bloomed bool not null default false,
  created timestamptz not null default now(),
  dies_at timestamptz not null default now() + interval '20 minutes'
);
-- >>>
create index if not exists spores_geog_idx on spores using gist (geog);
-- >>>
create index if not exists spores_alive_idx on spores (campus, dies_at desc);
-- >>>
-- ================================================================ START
-- Begin tracking whoever wrote a whisper.
--
-- The client passes a whisper id because that is the only handle it has ever
-- been given. The server turns it into an author inside this function and
-- does not give it back.
create or replace function hunt_start(target uuid)
returns text
language plpgsql security definer set search_path = public, extensions
as $fn$
declare
  uid  text := swarm_uid();
  prey text;
  st   record;
  me   extensions.geography;
  them extensions.geography;
  d    numeric;
  new_id uuid;
  b    text;
begin
  if uid is null then raise exception 'not signed in'; end if;

  select * into st from strikes where user_id = uid;
  if st.banned then raise exception 'account suspended'; end if;

  select w.author into prey
    from whispers w where w.id = target and w.dies_at > now();
  if prey is null then return 'lost'; end if;

  -- Hunting yourself would be a free way to test how close the floor really
  -- is, using a position you already know.
  if prey = uid then raise exception 'that one is yours'; end if;

  -- Blocking is mutual here. If either of you has silenced the other, the
  -- hunt does not start and neither is told why.
  if exists (select 1 from blocks
              where (blocker = uid and blocked = prey)
                 or (blocker = prey and blocked = uid)) then
    return 'lost';
  end if;

  select b.geog into me   from beacons b where b.user_id = uid;
  select b.geog into them from beacons b where b.user_id = prey;
  if me is null or them is null then return 'lost'; end if;

  d := extensions.st_distance(me, them);

  -- Starting a hunt from inside the floor is still the floor. No row is
  -- written, so there is nothing to ping for a second reading.
  if d < 10 then return 'mirage'; end if;

  -- One target at a time. Dropping the old hunt takes its alerts with it,
  -- which is the correct thing to happen to the person you stopped chasing.
  delete from hunts where hunter = uid;

  insert into hunts (hunter, quarry, whisper)
  values (uid, prey, target)
  returning id into new_id;

  b := room_band(d);

  -- They are told on the same tick you are. This is the whole rule.
  insert into hunt_alerts (quarry, hunt, band) values (prey, new_id, b);

  return b;
end;
$fn$;
-- >>>
-- ================================================================= PING
-- One tick of a live hunt. This is the function the ring is drawn from.
--
-- It returns a band and a state and nothing else — no bearing, no coordinate,
-- no id. `state` is what the prey is doing, which the hunter is entitled to
-- know because the prey was told they were being hunted before they did it.
create or replace function hunt_ping()
returns table (band text, state text, seconds int)
language plpgsql security definer set search_path = public, extensions
as $fn$
declare
  uid  text := swarm_uid();
  h    record;
  me   extensions.geography;
  them extensions.geography;
  d    numeric;
  quarry_frozen bool;
  b    text;
begin
  if uid is null then return; end if;

  select * into h from hunts
   where hunter = uid and dies_at > now()
   order by started desc limit 1;

  if h is null then
    return query select 'lost'::text, 'none'::text, 0;
    return;
  end if;

  select b.geog, b.frozen into them, quarry_frozen
    from beacons b where b.user_id = h.quarry;
  select b.geog into me from beacons b where b.user_id = uid;

  -- They closed the app, or their beacon aged out of the table. Losing a
  -- signal because someone left is not a failure state worth explaining.
  if me is null or them is null then
    delete from hunts where id = h.id;
    return query select 'lost'::text, 'gone'::text, 0;
    return;
  end if;

  d := extensions.st_distance(me, them);

  -- THE FLOOR. Ten metres, and the ring pops. What the hunter gets for
  -- closing the last thirty metres is the word 'mirage' and a deleted row:
  -- they must look up, and the app will not help them further. This is the
  -- one branch in this schema that must never be softened.
  if d < 10 then
    insert into nights (user_id, night, caught, closest)
      values (uid, current_date, 1, d)
      on conflict (user_id, night) do update
        set caught  = nights.caught + 1,
            closest = least(coalesce(nights.closest, excluded.closest),
                            excluded.closest);

    delete from hunts where id = h.id;
    return query select 'mirage'::text, 'burst'::text, 0;
    return;
  end if;

  -- Standing still dissolves the signal. It takes twelve seconds, so that
  -- freezing is a decision someone makes and holds, not a reflex — and so a
  -- hunter can still be beaten to it.
  if quarry_frozen then
    if h.froze_at is null then
      update hunts set state = 'frozen', froze_at = now() where id = h.id;
      return query select room_band(d), 'frozen'::text, 12;
      return;
    end if;

    if now() - h.froze_at > interval '12 seconds' then
      delete from hunts where id = h.id;
      return query select 'lost'::text, 'dissolved'::text, 0;
      return;
    end if;

    return query
      select room_band(d), 'frozen'::text,
             (12 - extract(epoch from now() - h.froze_at))::int;
    return;
  end if;

  -- They moved again after freezing. The clock resets rather than carrying
  -- over, because a half-finished freeze should not bank progress.
  if h.froze_at is not null then
    update hunts set froze_at = null, state = 'fleeing' where id = h.id;
  end if;

  b := room_band(d);

  -- Keep telling them. An alert on every tick would be noise, so this only
  -- speaks when the band actually changes — which is the moment the news is
  -- worth having anyway.
  if not exists (
    select 1 from hunt_alerts a
     where a.hunt = h.id and a.band = b
       and a.created > now() - interval '20 seconds'
  ) then
    insert into hunt_alerts (quarry, hunt, band) values (h.quarry, h.id, b);
  end if;

  update hunts set state = 'open' where id = h.id and state <> 'open';

  return query select b, 'open'::text,
                      greatest(0, extract(epoch from h.dies_at - now())::int);
end;
$fn$;
-- >>>
-- ================================================================== DROP
-- Stop hunting. Silent on the other end by design: the alerts go with the
-- row, and the person you were chasing simply stops hearing about it.
create or replace function hunt_drop()
returns void
language sql security definer set search_path = public as $fn$
  delete from hunts where hunter = swarm_uid();
$fn$;
-- >>>
-- ============================================================== THE PREY
-- What the hunted person is allowed to know: that it is happening, how many,
-- and how close the nearest one is. Never who.
create or replace function hunted_state()
returns table (hunters int, nearest text, frozen bool)
language plpgsql security definer set search_path = public, extensions
as $fn$
declare uid text := swarm_uid();
begin
  if uid is null then return; end if;

  return query
  select
    (select count(*)::int from hunts h
      where h.quarry = uid and h.dies_at > now()),
    coalesce((
      select a.band from hunt_alerts a
       where a.quarry = uid and a.created > now() - interval '30 seconds'
       order by case a.band
                  when 'mirage'   then 0 when 'critical' then 1
                  when 'hot'      then 2 when 'warm'     then 3
                  else 4 end,
                a.created desc
       limit 1
    ), 'none'),
    coalesce((select b.frozen from beacons b where b.user_id = uid), false);
end;
$fn$;
-- >>>
-- The freeze right itself. One flag, two functions, no counter to it — there
-- is deliberately no ability, bloom or purchase anywhere in this schema that
-- lets a hunter defeat this.
create or replace function freeze_signal(on_in bool default true)
returns bool
language plpgsql security definer set search_path = public, extensions
as $fn$
declare uid text := swarm_uid();
begin
  if uid is null then raise exception 'not signed in'; end if;

  update beacons set frozen = on_in where user_id = uid;

  -- Thawing restarts everyone's clock, not just the nearest hunter's.
  if not on_in then
    update hunts set froze_at = null, state = 'open'
     where quarry = uid and dies_at > now();
  end if;

  return on_in;
end;
$fn$;
-- >>>
-- Frozen people are not swept up. The signal is dissolved, which has to mean
-- dissolved to everyone and not merely to whoever is already chasing you.
-- This is 005's sweep with one clause added. Everything else — the campus
-- filter, the trend ordering, the 120 limit — is carried over verbatim,
-- because replacing a function is the easiest way to quietly delete
-- behaviour somebody relied on.
create or replace function sweep(
  radius_m numeric default 132, min_boosts int default 0)
returns table (
  id uuid, body text, klass text, boosts int,
  dies_at timestamptz, band text)
language plpgsql security definer set search_path = public, extensions as $fn$
declare me extensions.geography; uid text := swarm_uid();
begin
  if uid is null then raise exception 'not signed in'; end if;
  select b.geog into me from beacons b where b.user_id = uid;
  if me is null then return; end if;

  return query
  select w.id, w.body, w.klass, w.boosts, w.dies_at,
         room_band(extensions.st_distance(w.geog, me)::numeric)
    from whispers w
   where w.dies_at > now()
     and w.campus = 'pilot'
     and w.boosts >= min_boosts
     and extensions.st_dwithin(w.geog, me, radius_m)
     and not exists (select 1 from blocks b
                      where b.blocker = uid and b.blocked = w.author)
     -- the added clause: a dissolved signal is dissolved to everyone
     and not exists (select 1 from beacons fb
                      where fb.user_id = w.author and fb.frozen)
   order by w.boosts desc, w.created desc
   limit 120;
end;
$fn$;
-- >>>
-- ================================================================= SPORES
-- Drop a mark at your own beacon. As everywhere else, the client sends no
-- coordinate; the server reads the position you already pushed.
create or replace function spore_drop()
returns uuid
language plpgsql security definer set search_path = public, extensions
as $fn$
declare uid text := swarm_uid(); me extensions.geography; new_id uuid;
begin
  if uid is null then raise exception 'not signed in'; end if;

  select b.geog into me from beacons b where b.user_id = uid;
  if me is null then raise exception 'no beacon'; end if;

  -- Three at a time. Scarcity is a product rule, so it is enforced here and
  -- not by a greyed-out button.
  if (select count(*) from spores
       where author = uid and dies_at > now()) >= 3 then
    raise exception 'you have enough spores out';
  end if;

  insert into spores (author, geog) values (uid, me) returning id into new_id;
  return new_id;
end;
$fn$;
-- >>>
-- A spore blooms once its author has walked away from it. Until then it is
-- nobody's business, because until then it is a live position.
create or replace function spores_near(within_m numeric default 300)
returns table (id uuid, band text, bloomed bool, created timestamptz)
language plpgsql security definer set search_path = public, extensions
as $fn$
declare me extensions.geography; uid text := swarm_uid();
begin
  select b.geog into me from beacons b where b.user_id = uid;
  if me is null then return; end if;

  -- Bloom anything whose author is now more than 25 metres from it, the same
  -- number `_bloomSpores` uses in the engine.
  update spores s set bloomed = true
    from beacons b
   where s.author = b.user_id
     and not s.bloomed
     and s.dies_at > now()
     and extensions.st_distance(s.geog, b.geog) > 25;

  -- An author whose beacon has aged out entirely has certainly walked away.
  update spores s set bloomed = true
   where not s.bloomed and s.dies_at > now()
     and not exists (select 1 from beacons b where b.user_id = s.author);

  return query
  select s.id, room_band(extensions.st_distance(s.geog, me)), s.bloomed, s.created
    from spores s
   where s.dies_at > now()
     and s.bloomed
     and extensions.st_dwithin(s.geog, me, within_m);
end;
$fn$;
-- >>>
-- ================================================================= ROW LEVEL
alter table hunts       enable row level security;
-- >>>
alter table hunt_alerts enable row level security;
-- >>>
alter table spores      enable row level security;
-- >>>
-- `hunts` gets NO policy at all, deliberately. Both ids are in every row, so
-- there is no column-subset a client could safely be handed. Everything a
-- client needs comes back through the functions above, which return words.
-- >>>
drop policy if exists "alerts are mine" on hunt_alerts;
-- >>>
-- The quarry reads their own alerts, and this is the one place realtime is
-- pointed at: a phone subscribes here to be told it is being hunted. Safe to
-- subscribe to precisely because the row has no hunter in it.
create policy "alerts are mine" on hunt_alerts for select
  using (quarry = swarm_uid());
-- >>>
-- NOTE: `spores` has no select policy either. spores_near() strips the geog
-- and the author, and a direct select returns zero rows.
-- >>>
-- ---------------------------------------------------------------- realtime
-- Without this the policy above is correct and nothing is ever delivered.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table hunt_alerts;
    exception when duplicate_object then null;
    end;
  end if;
end $$;
-- >>>
-- ------------------------------------------------------------- 24h amnesia
-- Deleted, not archived — hunts included. A finished chase leaves no record
-- that it happened, which is the only version of this feature that is
-- compatible with the rest of the app.
create or replace function reap()
returns void language sql security definer set search_path = public as $fn$
  delete from whispers    where dies_at < now() - interval '1 minute';
  delete from beacons     where seen    < now() - interval '30 minutes';
  delete from nights      where night   < current_date - 1;
  delete from hunts       where dies_at < now();
  delete from hunt_alerts where dies_at < now();
  delete from spores      where dies_at < now();
$fn$;
