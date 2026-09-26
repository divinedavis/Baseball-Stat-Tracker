-- Reserve AI quota atomically before the Claude call, and finally lock the
-- quota functions away from client roles.
--
-- Two problems this closes:
--
-- 1. 20260830120000 (revoke EXECUTE on check_quota/increment_usage from
--    anon + authenticated) was committed but never applied: on 2026-09-26
--    prod still showed anon=X and authenticated=X on both functions, so any
--    holder of the bundled anon key could burn another user's allowance by
--    id. The revokes are repeated here so applying this file is enough.
--
-- 2. The edge functions did check_quota -> Claude -> increment_usage. The
--    check and the increment were separate statements with a multi-second
--    Claude call in between, so N concurrent requests all passed the check
--    and a free user could fire many paid analyses. reserve_quota() takes a
--    per-user/kind transaction advisory lock, re-checks and increments in one
--    transaction; release_quota() refunds a reservation when the Claude call
--    (or the work before it) fails.
--
-- Both new functions are SECURITY DEFINER with a pinned search_path and are
-- executable by service_role only (the edge functions' client).
--
-- Idempotent: safe to re-run.

create or replace function public.reserve_quota(p_user uuid, p_kind text)
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
  r record;
begin
  if p_kind not in ('swing', 'question') then
    return query select 'free'::ai_tier, false, 'unknown_kind'::text, 0, 0;
    return;
  end if;

  -- Serialise reservations for this user+kind until the transaction ends.
  perform pg_advisory_xact_lock(hashtextextended(p_user::text || ':' || p_kind, 0));

  select * into r from public.check_quota(p_user, p_kind);
  if r.allowed then
    perform public.increment_usage(p_user, p_kind);
  end if;

  -- Remaining counts are reported as they were before this reservation,
  -- matching what check_quota returned to the edge functions previously.
  return query select r.tier, r.allowed, r.reason, r.monthly_remaining, r.daily_remaining;
end;
$$;

create or replace function public.release_quota(p_user uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_period date := date_trunc('month', now())::date;
  v_day date := current_date;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user::text || ':' || p_kind, 0));
  if p_kind = 'swing' then
    update public.usage_counters
       set swings_used = greatest(swings_used - 1, 0)
     where user_id = p_user and period = v_period;
    update public.daily_usage
       set swings_used = greatest(swings_used - 1, 0)
     where user_id = p_user and day = v_day;
  elsif p_kind = 'question' then
    update public.usage_counters
       set questions_used = greatest(questions_used - 1, 0)
     where user_id = p_user and period = v_period;
  end if;
end;
$$;

-- Supabase's default privileges grant EXECUTE on new public functions to
-- anon and authenticated directly, so PUBLIC alone is not enough.
revoke all on function public.check_quota(uuid, text)     from public, anon, authenticated;
revoke all on function public.increment_usage(uuid, text) from public, anon, authenticated;
revoke all on function public.reserve_quota(uuid, text)   from public, anon, authenticated;
revoke all on function public.release_quota(uuid, text)   from public, anon, authenticated;

grant execute on function public.check_quota(uuid, text)     to service_role;
grant execute on function public.increment_usage(uuid, text) to service_role;
grant execute on function public.reserve_quota(uuid, text)   to service_role;
grant execute on function public.release_quota(uuid, text)   to service_role;

notify pgrst, 'reload schema';
