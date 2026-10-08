-- Hard ceilings on AI spend per user.
--
-- 1. Pro had monthly_questions = -1 (unlimited), so one Pro account (or a
--    script holding its session) could run Claude without bound. Pro now
--    gets a 1000/month ceiling (~33/day) — far above real use. App and
--    store copy say "up to 1,000 AI questions a month", never "unlimited".
-- 2. reserve_quota had no per-minute limit, so a tier's whole monthly
--    allowance could be fired in a burst. It now refuses with reason
--    'rate_limited' past RATE_* calls per user+kind per rolling minute
--    bucket (questions 10/min, swings 3/min). Refused calls don't count.
--
-- ai_rate_buckets is service_role only; reserve_quota prunes the caller's
-- buckets older than an hour on every call, so it stays tiny.
--
-- Idempotent: safe to re-run.

update public.tier_limits set monthly_questions = 1000
 where tier = 'pro' and monthly_questions < 0;

create table if not exists public.ai_rate_buckets (
  user_id uuid not null references auth.users on delete cascade,
  kind text not null,
  minute timestamptz not null,
  calls int not null default 0,
  primary key (user_id, kind, minute)
);
alter table public.ai_rate_buckets enable row level security;
revoke all on public.ai_rate_buckets from anon, authenticated;
grant select, insert, update, delete on public.ai_rate_buckets to service_role;

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
  v_minute timestamptz := date_trunc('minute', now());
  v_limit int;
  v_calls int;
begin
  if p_kind not in ('swing', 'question') then
    return query select 'free'::ai_tier, false, 'unknown_kind'::text, 0, 0;
    return;
  end if;
  v_limit := case p_kind when 'question' then 10 else 3 end;

  -- Serialise reservations for this user+kind until the transaction ends.
  perform pg_advisory_xact_lock(hashtextextended(p_user::text || ':' || p_kind, 0));

  delete from public.ai_rate_buckets b
   where b.user_id = p_user and b.minute < now() - interval '1 hour';

  select coalesce(sum(b.calls), 0) into v_calls
    from public.ai_rate_buckets b
   where b.user_id = p_user and b.kind = p_kind and b.minute = v_minute;

  select * into r from public.check_quota(p_user, p_kind);

  if r.allowed and v_calls >= v_limit then
    return query select r.tier, false, 'rate_limited'::text, r.monthly_remaining, r.daily_remaining;
    return;
  end if;

  if r.allowed then
    perform public.increment_usage(p_user, p_kind);
    insert into public.ai_rate_buckets as b (user_id, kind, minute, calls)
         values (p_user, p_kind, v_minute, 1)
    on conflict (user_id, kind, minute) do update set calls = b.calls + 1;
  end if;

  -- Remaining counts are reported as they were before this reservation,
  -- matching what check_quota returned to the edge functions previously.
  return query select r.tier, r.allowed, r.reason, r.monthly_remaining, r.daily_remaining;
end;
$$;

revoke all on function public.reserve_quota(uuid, text) from public, anon, authenticated;
grant execute on function public.reserve_quota(uuid, text) to service_role;

notify pgrst, 'reload schema';
