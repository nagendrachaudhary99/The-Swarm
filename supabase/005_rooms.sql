-- Migration 005 · rooms, membership and chat
--
-- A whisper is a thing you shout into the dark and lose. A room is the other
-- half of the product: somewhere two people who found each other can actually
-- talk. It keeps every rule the rest of this schema keeps —
--
--   * a room's coordinate never leaves Postgres. The client learns a BAND,
--     the same five words a whisper gets, and nothing else.
--   * you cannot join a room you are not standing near. Distance is checked
--     here, against your beacon, not against anything the phone claims.
--   * inside a room you are a handle — HERON-2 — that means nothing outside
--     it and cannot be traced back to a session, an address, or another room.
--   * everything dies. A room has a lifespan, its messages die with it, and
--     reap() deletes rather than archives.
-- >>>
-- ------------------------------------------------------------------- rooms
create table if not exists rooms (
  id       uuid primary key default gen_random_uuid(),
  host     text not null,                                -- swarm_uid(), never returned
  title    text not null check (char_length(title) between 1 and 60),
  geog     extensions.geography(point, 4326) not null,   -- never leaves this table
  radius_m int  not null default 120 check (radius_m between 30 and 400),
  campus   text not null default 'pilot',
  created  timestamptz not null default now(),
  dies_at  timestamptz not null
);
-- >>>
create index if not exists rooms_geog_idx on rooms using gist (geog);
-- >>>
create index if not exists rooms_alive_idx on rooms (campus, dies_at desc);
-- >>>
-- One room per host at a time, enforced by the database rather than by a
-- disabled button, so it survives someone driving the API directly.
--
-- This wants to be a partial unique index on (host) where dies_at > now(),
-- and cannot be: now() is not immutable, so Postgres refuses it in an index
-- predicate. A trigger is the version of the rule that actually holds, and it
-- has the better error message anyway.
create or replace function rooms_one_per_host()
returns trigger language plpgsql set search_path = public as $fn$
begin
  if exists (select 1 from rooms
              where host = new.host and dies_at > now() and id <> new.id) then
    raise exception 'you already have a room open';
  end if;
  return new;
end;
$fn$;
-- >>>
drop trigger if exists rooms_one_per_host_trg on rooms;
-- >>>
create trigger rooms_one_per_host_trg
  before insert on rooms
  for each row execute function rooms_one_per_host();
-- >>>
-- -------------------------------------------------------------- membership
-- `handle` is the whole identity model. It is assigned on join, it is stable
-- for the life of the room so a conversation can be followed, and it is
-- reused across rooms by different people so it identifies nobody.
create table if not exists room_members (
  room     uuid not null references rooms(id) on delete cascade,
  user_id  text not null,
  handle   text not null,
  joined   timestamptz not null default now(),
  primary key (room, user_id)
);
-- >>>
-- The PK covers (room, …); this covers the other direction, which is how
-- "which rooms am I in" and every RLS check on messages read the table.
create index if not exists room_members_user_idx on room_members (user_id);
-- >>>
-- ---------------------------------------------------------------- messages
-- `handle` is denormalised on purpose: history must be readable without
-- joining to membership, so that leaving a room takes your row with it and
-- what you said stays anonymous rather than becoming unattributed.
create table if not exists messages (
  id      uuid primary key default gen_random_uuid(),
  room    uuid not null references rooms(id) on delete cascade,
  author  text not null,
  handle  text not null,
  body    text not null check (char_length(body) between 1 and 240),
  said    timestamptz not null default now(),
  dies_at timestamptz not null
);
-- >>>
create index if not exists messages_room_idx on messages (room, said desc);
-- >>>
create index if not exists messages_dead_idx on messages (dies_at);
-- >>>
-- ------------------------------------------------------------------ handles
-- Twelve creatures and a number. Collisions across rooms are the point.
create or replace function room_handle(n int)
returns text language sql immutable set search_path = public as $fn$
  select (array['HERON','OTTER','MOTH','WREN','PIKE','HARE',
                'STOAT','RAVEN','NEWT','SHREW','LARK','ADDER'])[1 + (n % 12)]
         || '-' || (1 + n / 12)::text;
$fn$;
-- >>>
-- --------------------------------------------------------------- band maths
-- The same ladder whisper_band() uses, so a room and a whisper at the same
-- distance read identically. Under ten metres it refuses to say more.
create or replace function room_band(d numeric)
returns text language sql immutable set search_path = public as $fn$
  select case
    when d is null then 'lost'
    when d < 10  then 'mirage'
    when d < 30  then 'critical'
    when d < 80  then 'hot'
    when d < 180 then 'warm'
    else 'cold' end;
$fn$;
-- >>>
-- ------------------------------------------------------------------- OPEN
-- Opened at your beacon. The client sends no coordinate, exactly as posting a
-- whisper sends none — the server reads the position you already pushed.
create or replace function room_open(
  title_in text, radius_in int default 120, minutes_in int default 60)
returns uuid language plpgsql security definer set search_path = public, extensions as $fn$
declare me extensions.geography; uid text := swarm_uid();
        st record; verdict text; new_id uuid;
begin
  if uid is null then raise exception 'not signed in'; end if;

  select * into st from strikes where user_id = uid;
  if st.banned then raise exception 'account suspended'; end if;
  if st.muted_until is not null and st.muted_until > now() then
    raise exception 'muted until %', st.muted_until;
  end if;

  -- A room title is public to everyone in range, so it is screened exactly
  -- like a whisper body.
  verdict := screen(title_in);
  if verdict = 'block' then raise exception 'blocked by filter'; end if;

  select b.geog into me from beacons b where b.user_id = uid;
  if me is null then raise exception 'no beacon'; end if;

  delete from rooms where host = uid and dies_at <= now();

  insert into rooms (host, title, geog, radius_m, dies_at)
  values (uid, title_in, me,
          greatest(30, least(400, radius_in)),
          now() + make_interval(mins => greatest(5, least(180, minutes_in))))
  returning id into new_id;

  -- The host is member zero, so a room is never empty.
  insert into room_members (room, user_id, handle)
  values (new_id, uid, room_handle(0));

  if verdict = 'flag' then
    insert into reports (reporter, kind, target, reason, snapshot, author)
    -- 'circle' is what 003_safety called this feature before it existed;
    -- reports.kind still only permits post | message | circle.
    values ('auto-filter', 'circle', new_id::text, 'other', title_in, uid);
  end if;

  return new_id;
end;
$fn$;
-- >>>
-- ------------------------------------------------------------------- NEAR
-- What the radar draws. Bands and counts, never a coordinate and never a host.
-- The parameter is `within_m`, not `radius_m`: rooms HAS a radius_m column,
-- and a plpgsql variable sharing a column's name makes every reference to it
-- ambiguous rather than merely confusing.
drop function if exists rooms_near(numeric);
-- >>>
create or replace function rooms_near(within_m numeric default 300)
returns table (
  id uuid, title text, band text, members int,
  dies_at timestamptz, joined bool, in_range bool)
language plpgsql security definer set search_path = public, extensions as $fn$
declare me extensions.geography; uid text := swarm_uid();
begin
  if uid is null then raise exception 'not signed in'; end if;
  select b.geog into me from beacons b where b.user_id = uid;
  if me is null then return; end if;

  return query
  select r.id,
         r.title,
         room_band(extensions.st_distance(r.geog, me)::numeric),
         (select count(*)::int from room_members m where m.room = r.id),
         r.dies_at,
         exists (select 1 from room_members m
                  where m.room = r.id and m.user_id = uid),
         extensions.st_distance(r.geog, me) <= r.radius_m
    from rooms r
   where r.dies_at > now()
     and r.campus = 'pilot'
     and extensions.st_dwithin(r.geog, me, within_m)
     -- a room whose host you blocked is a room you never see
     and not exists (select 1 from blocks b
                      where b.blocker = uid and b.blocked = r.host)
   order by extensions.st_distance(r.geog, me);
end;
$fn$;
-- >>>
-- ------------------------------------------------------------------- JOIN
-- The door is physical. You are inside the radius or you are not in the room.
create or replace function room_join(target uuid)
returns text language plpgsql security definer set search_path = public, extensions as $fn$
declare me extensions.geography; uid text := swarm_uid();
        r record; n int; h text; st record;
begin
  if uid is null then raise exception 'not signed in'; end if;

  select * into st from strikes where user_id = uid;
  if st.banned then raise exception 'account suspended'; end if;

  select * into r from rooms where id = target and dies_at > now();
  if r is null then raise exception 'no such room'; end if;

  select handle into h from room_members where room = target and user_id = uid;
  if h is not null then return h; end if;          -- already in, idempotent

  select b.geog into me from beacons b where b.user_id = uid;
  if me is null then raise exception 'no beacon'; end if;
  if extensions.st_distance(r.geog, me) > r.radius_m then
    raise exception 'out of range';
  end if;

  select count(*)::int into n from room_members where room = target;
  h := room_handle(n);
  insert into room_members (room, user_id, handle) values (target, uid, h);
  return h;
end;
$fn$;
-- >>>
create or replace function room_leave(target uuid)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  if swarm_uid() is null then raise exception 'not signed in'; end if;
  delete from room_members where room = target and user_id = swarm_uid();
end;
$fn$;
-- >>>
-- -------------------------------------------------------------------- SAY
create or replace function room_say(target uuid, body_in text)
returns uuid language plpgsql security definer set search_path = public as $fn$
declare uid text := swarm_uid(); h text; r record;
        st record; verdict text; recent int; new_id uuid;
begin
  if uid is null then raise exception 'not signed in'; end if;

  select * into st from strikes where user_id = uid;
  if st.banned then raise exception 'account suspended'; end if;
  if st.muted_until is not null and st.muted_until > now() then
    raise exception 'muted until %', st.muted_until;
  end if;

  select * into r from rooms where id = target and dies_at > now();
  if r is null then raise exception 'no such room'; end if;

  select handle into h from room_members where room = target and user_id = uid;
  if h is null then raise exception 'not in this room'; end if;

  verdict := screen(body_in);
  if verdict = 'block' then raise exception 'blocked by filter'; end if;

  -- Twenty a minute. A conversation, not a firehose.
  select count(*)::int into recent from messages
   where author = uid and said > now() - interval '1 minute';
  if recent >= 20 then raise exception 'rate_limit'; end if;

  insert into messages (room, author, handle, body, dies_at)
  values (target, uid, h, body_in, r.dies_at)
  returning id into new_id;

  if verdict = 'flag' then
    insert into reports (reporter, kind, target, reason, snapshot, author)
    values ('auto-filter', 'message', new_id::text, 'other', body_in, uid);
  end if;

  return new_id;
end;
$fn$;
-- >>>
-- ---------------------------------------------------------------- HISTORY
-- Members only, and it returns handles rather than authors, so the shape of
-- the reply is the shape the UI is allowed to know.
create or replace function room_history(target uuid, limit_in int default 60)
returns table (id uuid, handle text, body text, said timestamptz, mine bool)
language plpgsql security definer set search_path = public as $fn$
declare uid text := swarm_uid();
begin
  if uid is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from room_members m
                  where m.room = target and m.user_id = uid) then
    raise exception 'not in this room';
  end if;

  return query
  select m.id, m.handle, m.body, m.said, m.author = uid
    from messages m
   where m.room = target
     and m.dies_at > now()
     -- someone you blocked is silent to you, without either of you being told
     and not exists (select 1 from blocks b
                      where b.blocker = uid and b.blocked = m.author)
   order by m.said desc
   limit greatest(1, least(200, limit_in));
end;
$fn$;
-- >>>
-- Block the author of a message, without ever learning who they are. Mirrors
-- block_author() for posts.
create or replace function block_speaker(target uuid)
returns bool language plpgsql security definer set search_path = public as $fn$
declare a text; uid text := swarm_uid();
begin
  if uid is null then raise exception 'not signed in'; end if;
  select author into a from messages where id = target;
  if a is null or a = uid then return false; end if;
  insert into blocks (blocker, blocked) values (uid, a) on conflict do nothing;
  return true;
end;
$fn$;
-- >>>
-- ------------------------------------------------------------------ POLICY
alter table rooms        enable row level security;
-- >>>
alter table room_members enable row level security;
-- >>>
alter table messages     enable row level security;
-- >>>
-- rooms has NO select policy, for the same reason whispers has none: the row
-- contains a coordinate. Every read goes through rooms_near().
drop policy if exists "rooms are read through rooms_near" on rooms;
-- >>>
-- You may see your own membership and nobody else's. Two rows of someone
-- else's membership would be enough to tell that two handles are one person.
drop policy if exists "my membership" on room_members;
-- >>>
create policy "my membership" on room_members for select
  using (user_id = (select swarm_uid()));
-- >>>
-- Messages carry no geography, so members may select them directly — which is
-- what makes Realtime work. The subquery form matters: swarm_uid() is called
-- once per query here, not once per row.
drop policy if exists "read rooms i am in" on messages;
-- >>>
create policy "read rooms i am in" on messages for select
  using (exists (select 1 from room_members m
                  where m.room = messages.room
                    and m.user_id = (select swarm_uid())));
-- >>>
-- No insert/update/delete policy anywhere: writing is what the RPCs are for,
-- and they check distance, membership, strikes and the filter first.
-- >>>
-- ------------------------------------------------------------ 24h amnesia
-- reap() gains the new tables. Messages go with their room by cascade; this
-- catches the rooms themselves and any message that outlived its own clock.
create or replace function reap()
returns void language sql security definer set search_path = public as $fn$
  delete from whispers where dies_at < now() - interval '1 minute';
  delete from beacons  where seen    < now() - interval '30 minutes';
  delete from nights   where night   < current_date - 1;
  delete from messages where dies_at < now() - interval '1 minute';
  delete from rooms    where dies_at < now() - interval '1 minute';
$fn$;
-- >>>
-- --------------------------------------------------- trend, and what zoom means
-- Zooming out does not mean "send me everything further away" — that is how a
-- map turns into soup and how a payload turns into a leak. It means "only the
-- loud ones". So the client sends the radius it is showing AND the floor it
-- wants, and the server refuses to return the quiet whispers at wide zoom
-- rather than trusting a phone to drop them after the fact.
--
-- Trend is boosts. A whisper nobody boosted is legible only when you are
-- standing near enough to have found it yourself.
--
-- The old one-argument sweep() is dropped rather than overloaded: leaving both
-- would make sweep(radius_m => x) ambiguous and every call would fail.
drop function if exists sweep(numeric);
-- >>>
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
   order by w.boosts desc, w.created desc
   limit 120;
end;
$fn$;
-- >>>
-- The index that makes the zoomed-out query cheap: the loud ones, still alive,
-- found without reading the quiet majority.
create index if not exists whispers_trend_idx
  on whispers (campus, boosts desc, dies_at desc);
