-- Ayos database setup. Run this once in Supabase: SQL Editor > New query > paste > Run.

create sequence if not exists public.report_seq;

create table if not exists public.reports (
  id         text primary key default ('AY-' || lpad(nextval('public.report_seq')::text, 4, '0')),
  data       jsonb not null,                       -- location, category, descriptions, status, log, etc.
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.reports enable row level security;

grant usage on sequence public.report_seq to anon;
grant select, insert, update on public.reports to anon;   -- no delete

create policy "read reports"   on public.reports for select to anon using (true);
create policy "file reports"   on public.reports for insert to anon with check (true);
create policy "update reports" on public.reports for update to anon using (true) with check (true);
