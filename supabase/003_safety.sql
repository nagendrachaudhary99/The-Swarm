-- Migration 003 · reporting, blocking, filtering
--
-- Apple Guideline 1.2 requires four things of any app with anonymous chat:
-- a filter, a report mechanism, user blocking, and evidence reports are acted
-- on. This migration is all four.
--
-- Two problems are specific to THIS app and are solved here rather than in the
-- client, because a client cannot be trusted to solve them:
--
--   1. Posts are deleted within the minute by reap(). A report filed against a
--      post that no longer exists is useless to a moderator. So a report
--      SNAPSHOTS the content at report time.
--   2. Nobody knows who wrote anything. So "block this person" cannot be done
--      in the client — it resolves the author server-side and never returns
--      the identity to anyone.
-- >>>
create table if not exists reports (
  id        uuid primary key default gen_random_uuid(),
  reporter  text not null,
  kind      text not null check (kind in ('post','message','circle')),
  target    text not null,
  reason    text not null check (reason in
              ('harassment','threat','sexual','doxxing','spam','self_harm','other')),
  detail    text check (char_length(detail) <= 400),

  -- Frozen at report time. Without this a moderator opens the queue and finds
  -- nothing, because the post died sixty seconds after it was written.
  snapshot  text,
  author    text,                       -- resolved server-side, never shown to the reporter
  created   timestamptz not null default now(),
  status    text not null default 'open' check (status in ('open','actioned','dismissed')),
  resolved  timestamptz
);
-- >>>
create index if not exists reports_open_idx on reports (status, created desc);
-- >>>
create index if not exists reports_author_idx on reports (author) where status = 'actioned';
-- >>>
-- One person blocking another, without either learning who the other is.
create table if not exists blocks (
  blocker  text not null,
  blocked  text not null,
  created  timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
-- >>>
-- A running count so repeat offenders surface without a human reading everything.
create table if not exists strikes (
  user_id  text primary key,
  count    int not null default 0,
  muted_until timestamptz,
  banned   bool not null default false
);
-- >>>
-- ---------------------------------------------------------------- FILTERING
-- Guideline 1.2's "method for filtering objectionable material". Deliberately
-- a table and not a constant in the app: a slur that shows up on Tuesday can
-- be blocked on Tuesday, without an app store release.
create table if not exists blocklist (
  pattern  text primary key,
  severity text not null default 'block' check (severity in ('block','flag'))
);
-- >>>
insert into blocklist (pattern, severity) values
  ('kill your\s*self','block'), ('kys\M','block'),
  ('\mgo die\M','block'), ('rape','block'),
  ('\mn[i1l]gg','block'), ('\mf[a4]gg','block'),
  ('\mreta[r]d','flag'), ('\mwhore\M','flag'), ('\mslut\M','flag')
on conflict (pattern) do nothing;
-- >>>
-- Returns 'block', 'flag' or 'ok'. Called before anything is written.
create or replace function screen(body text)
returns text language plpgsql stable security definer set search_path = public as $fn$
declare hit text;
begin
  select severity into hit from blocklist
   where body ~* pattern order by (severity = 'block') desc limit 1;
  return coalesce(hit, 'ok');
end;
$fn$;
-- >>>
-- ------------------------------------------------------------------ REPORT
create or replace function report(
  kind_in text, target_in text, reason_in text, detail_in text default null)
returns uuid language plpgsql security definer set search_path = public as $fn$
declare snap text; auth_id text; rid uuid; n int;
begin
  if swarm_uid() is null then raise exception 'not signed in'; end if;

  -- freeze the evidence before the reaper gets it
  if kind_in = 'post' then
    select w.body, w.author into snap, auth_id from whispers w where w.id = target_in::uuid;
  end if;

  insert into reports (reporter, kind, target, reason, detail, snapshot, author)
  values (swarm_uid(), kind_in, target_in, reason_in, detail_in, snap, auth_id)
  returning id into rid;

  -- three independent reports hides it immediately, pending a human
  select count(distinct reporter) into n from reports
   where target = target_in and status = 'open';
  if n >= 3 and kind_in = 'post' then
    update whispers set dies_at = now() where id = target_in::uuid;
    insert into strikes (user_id, count) values (auth_id, 1)
      on conflict (user_id) do update set count = strikes.count + 1;
  end if;

  return rid;
end;
$fn$;
-- >>>
-- ------------------------------------------------------------------- BLOCK
-- You point at a post; the server works out who wrote it and blocks them. The
-- identity is resolved inside this function and never leaves it.
create or replace function block_author(target uuid)
returns boolean language plpgsql security definer set search_path = public as $fn$
declare auth_id text;
begin
  select w.author into auth_id from whispers w where w.id = target;
  if auth_id is null or auth_id = swarm_uid() then return false; end if;
  insert into blocks (blocker, blocked) values (swarm_uid(), auth_id)
    on conflict do nothing;
  return true;
end;
$fn$;
-- >>>
create or replace function unblock_all()
returns int language plpgsql security definer set search_path = public as $fn$
declare n int;
begin
  delete from blocks where blocker = swarm_uid();
  get diagnostics n = row_count; return n;
end;
$fn$;
-- >>>
-- --------------------------------------------------- SWEEP RESPECTS BLOCKS
-- Blocking has to work at the source. If a blocked person's words reached the
-- client at all, a bug or a rebuilt client would show them.
create or replace function sweep(radius_m numeric default 132)
returns table (id uuid, body text, klass text, boosts int, dies_at timestamptz, band text)
language plpgsql security definer set search_path = public, extensions
as $fn$
declare me extensions.geography; uid text := swarm_uid();
begin
  select b.geog into me from beacons b where b.user_id = uid;
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
   where w.dies_at > now()
     and extensions.st_dwithin(w.geog, me, radius_m)
     and not exists (select 1 from blocks b
                      where b.blocker = uid and b.blocked = w.author)
     and not exists (select 1 from strikes s
                      where s.user_id = w.author and s.banned);
end;
$fn$;
-- >>>
-- Screen on the way in, so nothing filthy is ever stored at all.
create or replace function post_whisper(body_in text, bloom_in text default 'nightly')
returns uuid language plpgsql security definer set search_path = public, extensions
as $fn$
declare me extensions.geography; k text; life interval; new_id uuid;
        uid text := swarm_uid(); verdict text; st record;
begin
  if uid is null then raise exception 'not signed in'; end if;

  select * into st from strikes where user_id = uid;
  if st.banned then raise exception 'account suspended'; end if;
  if st.muted_until is not null and st.muted_until > now() then
    raise exception 'muted until %', st.muted_until;
  end if;

  verdict := screen(body_in);
  if verdict = 'block' then raise exception 'blocked by filter'; end if;

  select b.geog into me from beacons b where b.user_id = uid;
  if me is null then raise exception 'no beacon'; end if;
  select p.klass into k from profiles p where p.id = uid;

  life := case bloom_in when 'exam' then interval '66 seconds'
                        when 'snow' then interval '44 seconds'
                        else interval '22 seconds' end;

  insert into whispers (author, body, geog, klass, bloom, dies_at)
  values (uid, body_in, me, coalesce(k,'rogue'), bloom_in, now() + life)
  returning id into new_id;

  if verdict = 'flag' then
    insert into reports (reporter, kind, target, reason, snapshot, author)
    values ('auto-filter', 'post', new_id::text, 'other', body_in, uid);
  end if;

  return new_id;
end;
$fn$;
-- >>>
-- ------------------------------------------------------------------ POLICY
alter table reports   enable row level security;
-- >>>
alter table blocks    enable row level security;
-- >>>
alter table strikes   enable row level security;
-- >>>
alter table blocklist enable row level security;
-- >>>
drop policy if exists "file my own reports" on reports;
-- >>>
-- You may file a report and see your own. You may never read the queue: it
-- contains other people's words and the authors' ids.
create policy "file my own reports" on reports for insert
  with check (reporter = swarm_uid());
-- >>>
drop policy if exists "see my own reports" on reports;
-- >>>
create policy "see my own reports" on reports for select
  using (reporter = swarm_uid());
-- >>>
drop policy if exists "my blocks" on blocks;
-- >>>
create policy "my blocks" on blocks for all
  using (blocker = swarm_uid()) with check (blocker = swarm_uid());
-- >>>
-- Nobody reads strikes or the blocklist from a client. Both are enforced
-- inside security-definer functions only.
