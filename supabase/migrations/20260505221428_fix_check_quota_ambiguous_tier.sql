-- The original `check_quota` had `where tier = v_tier`, which is ambiguous
-- because both `public.tier_limits.tier` and the function's `tier` OUT
-- parameter from `RETURNS TABLE` are in scope. Postgres rejects with
-- 42702 "column reference 'tier' is ambiguous". Fix by qualifying the
-- column.

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

revoke all on function public.check_quota(uuid, text) from public;
grant execute on function public.check_quota(uuid, text) to service_role;
