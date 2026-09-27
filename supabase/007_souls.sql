-- Migration 007 · who else is out there
--
-- Until now the only evidence another person existed was a whisper they chose
-- to post. Open the app on a quiet night and it is indistinguishable from an
-- app with nobody in it — which is exactly what two people testing together
-- experienced, and it is the single most discouraging thing a social app can
-- do on first run.
--
-- This adds presence, and nothing else. It answers "how many people are near
-- you, and how near" using the same five band words everything else uses.
--
-- What it deliberately does NOT return:
--
--   * no user id, in any form. The rows are bare bands — there is no column
--     to correlate on, so two calls a minute apart cannot tell you whether
--     the person at HOT is the same person as before.
--   * no coordinate, as everywhere else.
--   * nothing under ten metres except the word 'mirage', because room_band
--     is the same ladder the whispers and the hunts use and the floor is not
--     negotiable here either.
--   * nobody who froze. A dissolved signal is dissolved to everyone; showing
--     a frozen person as a presence dot would be a hole straight through the
--     freeze right.
-- >>>
create or replace function souls_near(within_m numeric default 300)
returns table (band text)
language plpgsql security definer set search_path = public, extensions
as $fn$
declare me extensions.geography; uid text := swarm_uid();
begin
  if uid is null then raise exception 'not signed in'; end if;

  select b.geog into me from beacons b where b.user_id = uid;
  if me is null then return; end if;

  return query
  select room_band(extensions.st_distance(b.geog, me)::numeric)
    from beacons b
   where b.user_id <> uid                    -- you are not near yourself
     and b.campus = 'pilot'
     and not b.frozen                        -- the freeze right, honoured here
     -- Five minutes, not the reaper's thirty. A beacon that stale belongs to
     -- somebody who closed the app, and drawing them is a crowd that is not
     -- there — the opposite failure to the one this migration fixes.
     and b.seen > now() - interval '5 minutes'
     and extensions.st_dwithin(b.geog, me, within_m)
     and not exists (
       select 1 from blocks bl
        where (bl.blocker = uid and bl.blocked = b.user_id)
           or (bl.blocker = b.user_id and bl.blocked = uid))
   order by extensions.st_distance(b.geog, me)
   limit 60;
end;
$fn$;
-- >>>
-- The index that keeps this cheap once a building's worth of people are on:
-- alive beacons, by campus, before any distance maths happens.
create index if not exists beacons_alive_idx on beacons (campus, seen desc);
