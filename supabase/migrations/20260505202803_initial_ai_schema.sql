-- Barrel AI: subscription, usage, and history schema.
-- Tier caps are enforced in the edge functions but mirrored here as the
-- source of truth so quota checks can run inside Postgres without round-trips.

create type ai_tier as enum ('free', 'standard', 'pro');

create table public.subscriptions (
  user_id uuid primary key references auth.users on delete cascade,
  tier ai_tier not null default 'free',
  product_id text,
  original_transaction_id text,
  expires_at timestamptz,
  environment text check (environment in ('Sandbox','Production')),
  updated_at timestamptz not null default now()
);
create index on public.subscriptions (original_transaction_id);

create table public.usage_counters (
  user_id uuid not null references auth.users on delete cascade,
  period date not null,
  swings_used int not null default 0,
  questions_used int not null default 0,
  primary key (user_id, period)
);

create table public.daily_usage (
  user_id uuid not null references auth.users on delete cascade,
  day date not null,
  swings_used int not null default 0,
  primary key (user_id, day)
);

create table public.swing_analyses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  storage_path text not null,
  media_kind text not null check (media_kind in ('photo','video')),
  feedback text,
  model text,
  input_tokens int,
  output_tokens int,
  created_at timestamptz not null default now()
);
create index on public.swing_analyses (user_id, created_at desc);

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  role text not null check (role in ('user','assistant')),
  content text not null,
  swing_id uuid references public.swing_analyses on delete set null,
  created_at timestamptz not null default now()
);
create index on public.chat_messages (user_id, created_at);

create table public.tier_limits (
  tier ai_tier primary key,
  monthly_swings int not null,
  daily_swings int not null,
  monthly_questions int not null
);
insert into public.tier_limits values
  ('free',     2,  2,  5),
  ('standard', 15, 5,  30),
  ('pro',      50, 15, -1);

alter table public.subscriptions  enable row level security;
alter table public.usage_counters enable row level security;
alter table public.daily_usage    enable row level security;
alter table public.swing_analyses enable row level security;
alter table public.chat_messages  enable row level security;
alter table public.tier_limits    enable row level security;

create policy "subs_owner_read"     on public.subscriptions  for select using (auth.uid() = user_id);
create policy "usage_owner_read"    on public.usage_counters for select using (auth.uid() = user_id);
create policy "daily_owner_read"    on public.daily_usage    for select using (auth.uid() = user_id);
create policy "swings_owner_read"   on public.swing_analyses for select using (auth.uid() = user_id);
create policy "chat_owner_read"     on public.chat_messages  for select using (auth.uid() = user_id);
create policy "tier_limits_public"  on public.tier_limits    for select using (true);

create or replace function public.check_quota(p_user uuid, p_kind text)
returns table (
  tier ai_tier,
  allowed boolean,
  reason text,
  monthly_remaining int,
  daily_remaining int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tier ai_tier;
  v_expires timestamptz;
  v_period date := date_trunc('month', now())::date;
  v_day date := current_date;
  v_swings_month int;
  v_swings_day int;
  v_questions_month int;
  v_limits record;
begin
  select s.tier, s.expires_at into v_tier, v_expires
    from public.subscriptions s where s.user_id = p_user;
  if v_tier is null then v_tier := 'free'; end if;
  if v_tier <> 'free' and v_expires is not null and v_expires < now() then
    v_tier := 'free';
  end if;

  select * into v_limits from public.tier_limits where tier = v_tier;

  select coalesce(uc.swings_used,0), coalesce(uc.questions_used,0)
    into v_swings_month, v_questions_month
    from public.usage_counters uc
    where uc.user_id = p_user and uc.period = v_period;
  v_swings_month := coalesce(v_swings_month, 0);
  v_questions_month := coalesce(v_questions_month, 0);

  select coalesce(du.swings_used,0) into v_swings_day
    from public.daily_usage du
    where du.user_id = p_user and du.day = v_day;
  v_swings_day := coalesce(v_swings_day, 0);

  if p_kind = 'swing' then
    if v_swings_month >= v_limits.monthly_swings then
      return query select v_tier, false, 'monthly_swings_exhausted'::text,
        0, greatest(v_limits.daily_swings - v_swings_day, 0);
      return;
    end if;
    if v_swings_day >= v_limits.daily_swings then
      return query select v_tier, false, 'daily_swings_exhausted'::text,
        v_limits.monthly_swings - v_swings_month, 0;
      return;
    end if;
    return query select v_tier, true, null::text,
      v_limits.monthly_swings - v_swings_month,
      v_limits.daily_swings - v_swings_day;
  elsif p_kind = 'question' then
    if v_limits.monthly_questions >= 0 and v_questions_month >= v_limits.monthly_questions then
      return query select v_tier, false, 'monthly_questions_exhausted'::text, 0, 0;
      return;
    end if;
    return query select v_tier, true, null::text,
      case when v_limits.monthly_questions < 0 then -1
           else v_limits.monthly_questions - v_questions_month end,
      0;
  else
    return query select v_tier, false, 'unknown_kind'::text, 0, 0;
  end if;
end;
$$;

create or replace function public.increment_usage(p_user uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_period date := date_trunc('month', now())::date;
  v_day date := current_date;
begin
  if p_kind = 'swing' then
    insert into public.usage_counters (user_id, period, swings_used)
      values (p_user, v_period, 1)
      on conflict (user_id, period)
      do update set swings_used = usage_counters.swings_used + 1;
    insert into public.daily_usage (user_id, day, swings_used)
      values (p_user, v_day, 1)
      on conflict (user_id, day)
      do update set swings_used = daily_usage.swings_used + 1;
  elsif p_kind = 'question' then
    insert into public.usage_counters (user_id, period, questions_used)
      values (p_user, v_period, 1)
      on conflict (user_id, period)
      do update set questions_used = usage_counters.questions_used + 1;
  end if;
end;
$$;

revoke all on function public.check_quota(uuid, text) from public;
revoke all on function public.increment_usage(uuid, text) from public;
grant execute on function public.check_quota(uuid, text) to service_role;
grant execute on function public.increment_usage(uuid, text) to service_role;
