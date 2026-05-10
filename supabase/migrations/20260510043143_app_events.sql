-- Product-interaction event log for funnel analysis.
-- Each row is one user action (screen view, button tap, paywall shown, etc.).
-- Inserts come from the iOS app under the user's JWT; reads are limited to
-- the row's owner (so users can audit their own data) and service role.

create table public.app_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  event text not null,
  properties jsonb not null default '{}'::jsonb,
  app_version text,
  os_version text,
  device_model text,
  created_at timestamptz not null default now()
);

create index on public.app_events (user_id, created_at desc);
create index on public.app_events (event, created_at desc);
create index on public.app_events (created_at desc);

alter table public.app_events enable row level security;

create policy "events_owner_insert"
  on public.app_events for insert
  with check (auth.uid() = user_id);

create policy "events_owner_read"
  on public.app_events for select
  using (auth.uid() = user_id);
