-- Ayos database setup (v2). Safe to run again. Supabase: SQL Editor > New query > paste > Run.

create sequence if not exists public.report_seq;

create table if not exists public.reports (
  id         text primary key default ('AY-' || lpad(nextval('public.report_seq')::text, 4, '0')),
  data       jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.reports enable row level security;

-- Reset old policies from the first version
drop policy if exists "read reports"   on public.reports;
drop policy if exists "file reports"   on public.reports;
drop policy if exists "update reports" on public.reports;
drop policy if exists "staff update"   on public.reports;

-- Everyone can read (public status board). Only signed-in staff can change reports.
revoke insert, update, delete on public.reports from anon;
grant  select on public.reports to anon;
grant  select, update on public.reports to authenticated;
create policy "read reports" on public.reports for select to anon, authenticated using (true);
create policy "staff update" on public.reports for update to authenticated using (true) with check (true);

-- Students file reports through this function only. It merges duplicates atomically.
create or replace function public.submit_report(
  p_loc text, p_cat text, p_x text, p_photo text, p_qty int, p_urg int, p_sf boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  rid text; d jsonb; merged boolean := false;
  ms bigint := (extract(epoch from now()) * 1000)::bigint;
begin
  if coalesce(trim(p_loc), '') = '' or coalesce(trim(p_x), '') = '' then raise exception 'location and description are required'; end if;
  if p_cat not in ('furniture','electrical','water','restroom','safety','clean','equip','other') then raise exception 'bad category'; end if;
  p_qty := least(greatest(coalesce(p_qty, 1), 1), 99);
  p_urg := least(greatest(coalesce(p_urg, 1), 0), 2);

  select id into rid from reports
   where lower(data->>'loc') = lower(p_loc) and data->>'cat' = p_cat and (data->>'st')::int < 4
   order by created_at limit 1 for update;

  if rid is null then
    insert into reports(data) values (jsonb_build_object(
      'loc', p_loc, 'cat', p_cat, 'n', 1, 'q', p_qty, 'u', p_urg, 'sf', coalesce(p_sf, false),
      'st', 0, 'who', '', 'up', ms, 'res', null,
      'd',   jsonb_build_array(jsonb_build_object('x', p_x, 't', ms, 'p', p_photo)),
      'log', jsonb_build_array(jsonb_build_object('t', ms, 'x', 'Reported by student'))))
    returning id, data into rid, d;
  else
    merged := true;
    update reports set updated_at = now(), data = data || jsonb_build_object(
      'n',  (data->>'n')::int + 1,
      'q',  greatest((data->>'q')::int, p_qty),
      'u',  greatest((data->>'u')::int, p_urg),
      'sf', (data->>'sf')::boolean or coalesce(p_sf, false),
      'up', ms,
      'd',   (data->'d')   || jsonb_build_array(jsonb_build_object('x', p_x, 't', ms, 'p', p_photo)),
      'log', (data->'log') || jsonb_build_array(jsonb_build_object('t', ms, 'x', 'Another report merged (now ' || ((data->>'n')::int + 1) || ')')))
    where id = rid returning data into d;
  end if;

  return jsonb_build_object('id', rid, 'n', (d->>'n')::int, 'st', (d->>'st')::int, 'merged', merged);
end $$;

revoke all on function public.submit_report(text,text,text,text,int,int,boolean) from public;
grant execute on function public.submit_report(text,text,text,text,int,int,boolean) to anon, authenticated;
