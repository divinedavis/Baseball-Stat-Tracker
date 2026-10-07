-- Sandbox StoreKit purchases no longer unlock a paid AI tier for everyone.
--
-- App Store Connect sends sandbox notifications (TestFlight, Xcode builds,
-- App Review) to the same storekit-webhook as production. The webhook
-- records `environment` but check_quota ignored it, so a TestFlight tester's
-- free sandbox "purchase" of Pro bought real Claude calls on our bill.
--
-- Now a Sandbox subscription row only counts when:
--   * the user is on sandbox_tier_allowlist (owner / test accounts), or
--   * billing_settings.sandbox_grants_open_until is in the future — the
--     owner opens this window while a build is in App Review so the
--     reviewer's sandbox purchase works, e.g.
--       update public.billing_settings
--          set sandbox_grants_open_until = now() + interval '14 days';
-- Otherwise the user gets the free tier. Production rows and rows with a
-- NULL environment (manual grants) are unchanged.
--
-- Idempotent: safe to re-run.

create table if not exists public.sandbox_tier_allowlist (
  user_id uuid primary key references auth.users on delete cascade,
  note text,
  added_at timestamptz not null default now()
);
alter table public.sandbox_tier_allowlist enable row level security;

create table if not exists public.billing_settings (
  id boolean primary key default true check (id),
  sandbox_grants_open_until timestamptz
);
alter table public.billing_settings enable row level security;
insert into public.billing_settings (id) values (true) on conflict (id) do nothing;

-- Server-only tables: no client role touches them.
revoke all on public.sandbox_tier_allowlist, public.billing_settings from anon, authenticated;
grant select, insert, update, delete on public.sandbox_tier_allowlist, public.billing_settings to service_role;

-- Owner/test accounts that hold the long-lived (2099) sandbox Pro grants.
insert into public.sandbox_tier_allowlist (user_id, note)
select u.id, 'owner/test account (2026-10-07)'
  from auth.users u
 where u.id in ('5e7c96e0-55f1-4258-ad5a-d3490098cb62',
                '45caaccd-0c9d-45b9-9040-410530eed02b',
                '4684d88d-da45-47c5-be70-6de98b500d0f')
on conflict (user_id) do nothing;

-- The tier a user's quota is actually computed from.
create or replace function public.effective_tier(p_user uuid)
returns ai_tier
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tier ai_tier;
  v_expires timestamptz;
  v_env text;
begin
  select s.tier, s.expires_at, s.environment into v_tier, v_expires, v_env
    from public.subscriptions s where s.user_id = p_user;
  if v_tier is null then return 'free'; end if;
  if v_tier <> 'free' and v_expires is not null and v_expires < now() then
    return 'free';
  end if;
  if v_tier <> 'free' and v_env = 'Sandbox'
     and not exists (select 1 from public.sandbox_tier_allowlist a where a.user_id = p_user)
     and not exists (select 1 from public.billing_settings b
                      where b.sandbox_grants_open_until > now()) then
    return 'free';
  end if;
  return v_tier;
end;
$$;

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
  v_period date := date_trunc('month', now())::date;
  v_day date := current_date;
  v_swings_month int;
  v_swings_day int;
  v_questions_month int;
  v_limits record;
begin
  v_tier := public.effective_tier(p_user);

  select tl.* into v_limits from public.tier_limits tl where tl.tier = v_tier;

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

revoke all on function public.effective_tier(uuid) from public, anon, authenticated;
revoke all on function public.check_quota(uuid, text) from public, anon, authenticated;
grant execute on function public.effective_tier(uuid) to service_role;
grant execute on function public.check_quota(uuid, text) to service_role;

notify pgrst, 'reload schema';
