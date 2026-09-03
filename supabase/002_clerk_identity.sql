-- Migration 002 · provider-agnostic identity
--
-- Supabase Auth issues UUID subjects. Clerk issues strings like `user_2abc…`.
-- Rather than marry either one, every user column becomes text and every
-- policy asks swarm_uid(), which answers for whichever session is present.
-- Swapping auth providers later costs nothing.
-- >>>
create or replace function swarm_uid() returns text
language sql stable
as $fn$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', ''),
    auth.uid()::text
  );
$fn$;
-- >>>
alter table whispers drop constraint if exists whispers_author_fkey;
-- >>>
alter table beacons  drop constraint if exists beacons_user_id_fkey;
-- >>>
alter table nights   drop constraint if exists nights_user_id_fkey;
-- >>>
alter table boosts   drop constraint if exists boosts_user_id_fkey;
-- >>>
alter table profiles drop constraint if exists profiles_id_fkey;
-- >>>
alter table profiles alter column id      type text using id::text;
-- >>>
alter table whispers alter column author  type text using author::text;
-- >>>
alter table beacons  alter column user_id type text using user_id::text;
-- >>>
alter table nights   alter column user_id type text using user_id::text;
-- >>>
alter table boosts   alter column user_id type text using user_id::text;
-- >>>
create or replace function whisper_band(target uuid)
returns text language plpgsql security definer set search_path = public, extensions
as $fn$
declare d numeric;
begin
  select extensions.st_distance(w.geog, b.geog) into d
    from whispers w, beacons b
   where w.id = target and b.user_id = swarm_uid();
  if d is null then return 'lost';   end if;
  if d < 10    then return 'mirage'; end if;   -- the floor. permanent.
  if d < 30    then return 'critical'; end if;
  if d < 80    then return 'hot';    end if;
  if d < 180   then return 'warm';   end if;
  return 'cold';
end;
$fn$;
-- >>>
create or replace function sweep(radius_m numeric default 132)
returns table (id uuid, body text, klass text, boosts int, dies_at timestamptz, band text)
language plpgsql security definer set search_path = public, extensions
as $fn$
declare me extensions.geography;
begin
  select b.geog into me from beacons b where b.user_id = swarm_uid();
  if me is null then return; end if;
  return query
  select w.id, w.body, w.klass, w.boosts, w.dies_at,
         case
           when extensions.st_distance(w.geog, me) < 10  then 'mirage'
           when extensions.st_distance(w.geog, me) < 30  then 'critical'
           when extensions.st_distance(w.geog, me) < 80  then 'hot'
           when extensions.st_distance(w.geog, me) < 180 then 'warm'
           else 'cold' end
    from whispers w
   where w.dies_at > now() and extensions.st_dwithin(w.geog, me, radius_m);
end;
$fn$;
-- >>>
create or replace function post_whisper(body_in text, bloom_in text default 'nightly')
returns uuid language plpgsql security definer set search_path = public, extensions
as $fn$
declare me extensions.geography; k text; life interval; new_id uuid; uid text;
begin
  uid := swarm_uid();
  if uid is null then raise exception 'not signed in'; end if;
  select b.geog into me from beacons b where b.user_id = uid;
  if me is null then raise exception 'no beacon'; end if;
  select p.klass into k from profiles p where p.id = uid;
  life := case bloom_in when 'exam' then interval '66 seconds'
                        when 'snow' then interval '44 seconds'
                        else interval '22 seconds' end;
  insert into whispers (author, body, geog, klass, bloom, dies_at)
  values (uid, body_in, me, coalesce(k,'rogue'), bloom_in, now() + life)
  returning id into new_id;
  return new_id;
end;
$fn$;
-- >>>
create or replace function boost_whisper(target uuid)
returns int language plpgsql security definer set search_path = public, extensions
as $fn$
declare owner text; uid text := swarm_uid();
begin
  insert into boosts (whisper_id, user_id) values (target, uid) on conflict do nothing;
  if not found then return -1; end if;
  update whispers set boosts = boosts + 1, dies_at = dies_at + interval '4 seconds'
   where id = target returning author into owner;
  insert into nights (user_id, night, given) values (uid, current_date, 1)
    on conflict (user_id, night) do update set given = nights.given + 1;
  insert into nights (user_id, night, received) values (owner, current_date, 1)
    on conflict (user_id, night) do update set received = nights.received + 1;
  return 1;
end;
$fn$;
-- >>>
create or replace function beacon_set(lat double precision, lon double precision)
returns void language plpgsql security definer set search_path = public, extensions
as $fn$
begin
  insert into beacons (user_id, geog, seen)
  values (swarm_uid(), extensions.st_point(lon, lat)::extensions.geography, now())
  on conflict (user_id) do update set geog = excluded.geog, seen = now();
end;
$fn$;
-- >>>
drop policy if exists "own profile" on profiles;
-- >>>
create policy "own profile" on profiles for all
  using (id = swarm_uid()) with check (id = swarm_uid());
-- >>>
drop policy if exists "beacon is mine alone" on beacons;
-- >>>
create policy "beacon is mine alone" on beacons for all
  using (user_id = swarm_uid()) with check (user_id = swarm_uid());
-- >>>
drop policy if exists "my nights" on nights;
-- >>>
create policy "my nights" on nights for all
  using (user_id = swarm_uid()) with check (user_id = swarm_uid());
-- >>>
drop policy if exists "insert my own whisper" on whispers;
-- >>>
create policy "insert my own whisper" on whispers for insert
  with check (author = swarm_uid());
-- >>>
drop policy if exists "my boosts" on boosts;
-- >>>
create policy "my boosts" on boosts for all
  using (user_id = swarm_uid()) with check (user_id = swarm_uid());
