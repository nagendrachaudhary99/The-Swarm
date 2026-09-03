-- Migration 004 · close two de-anonymisation leaks introduced in 003
--
-- RLS is row-level, not column-level. Giving someone SELECT on "their own"
-- rows in `blocks` and `reports` handed them the OTHER party's user id — and
-- with a couple of blocks you could then tell whether two anonymous posts came
-- from the same person. That is precisely the thing this app promises is
-- impossible. Both tables are now unreadable from any client, and the small
-- amount a person legitimately needs to know comes back through functions that
-- return counts and statuses, never ids.
-- >>>
drop policy if exists "my blocks" on blocks;
-- >>>
drop policy if exists "see my own reports" on reports;
-- >>>
-- You may still create both. You may no longer read either.
create policy "block, do not read" on blocks for insert
  with check (blocker = swarm_uid());
-- >>>
-- What a person actually needs: how many people they have blocked.
create or replace function my_blocks()
returns int language sql security definer set search_path = public as $fn$
  select count(*)::int from blocks where blocker = swarm_uid();
$fn$;
-- >>>
-- And what happened to the reports they filed — no snapshot, no author.
create or replace function my_reports()
returns table (id uuid, kind text, reason text, status text, created timestamptz)
language sql security definer set search_path = public as $fn$
  select r.id, r.kind, r.reason, r.status, r.created
    from reports r where r.reporter = swarm_uid() order by r.created desc;
$fn$;
