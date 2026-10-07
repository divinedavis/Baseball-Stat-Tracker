-- Always rolls back (final RAISE 'ALL_TESTS_PASSED').
do $$
declare
  u uuid := gen_random_uuid();
  r record;
  i int;
begin
  insert into auth.users (id, email, aud, role) values (u, u || '@test.invalid', 'authenticated', 'authenticated');
  insert into public.subscriptions (user_id, tier, environment, expires_at)
       values (u, 'pro', 'Production', now() + interval '1 day');

  assert (select monthly_questions from public.tier_limits where tier = 'pro') = 1000,
         'pro needs a finite monthly question ceiling';
  assert not exists (select 1 from public.tier_limits where monthly_questions < 0 or monthly_swings < 0),
         'no tier may be unlimited';

  -- 10 questions in one minute pass, the 11th is rate_limited and not counted
  for i in 1..10 loop
    select * into r from public.reserve_quota(u, 'question');
    assert r.allowed, format('question %s should pass', i);
  end loop;
  select * into r from public.reserve_quota(u, 'question');
  assert not r.allowed and r.reason = 'rate_limited', '11th question/minute must be rate_limited';
  assert (select questions_used from public.usage_counters where user_id = u) = 10,
         'rate-limited call must not consume monthly quota';

  -- swings: 3/min
  for i in 1..3 loop
    select * into r from public.reserve_quota(u, 'swing');
    assert r.allowed, format('swing %s should pass', i);
  end loop;
  select * into r from public.reserve_quota(u, 'swing');
  assert not r.allowed and r.reason = 'rate_limited', '4th swing/minute must be rate_limited';

  -- next minute bucket opens again (simulate by aging the buckets)
  update public.ai_rate_buckets set minute = minute - interval '1 minute' where user_id = u;
  select * into r from public.reserve_quota(u, 'question');
  assert r.allowed, 'new minute should allow questions again';

  -- monthly ceiling: at 1000 used, pro is refused
  update public.usage_counters set questions_used = 1000 where user_id = u;
  update public.ai_rate_buckets set minute = minute - interval '5 minutes' where user_id = u;
  select * into r from public.reserve_quota(u, 'question');
  assert not r.allowed and r.reason = 'monthly_questions_exhausted', 'pro must stop at 1000/month';

  -- old buckets are pruned
  update public.ai_rate_buckets set minute = minute - interval '2 hours' where user_id = u;
  perform public.reserve_quota(u, 'swing');
  assert not exists (select 1 from public.ai_rate_buckets where user_id = u and minute < now() - interval '1 hour'),
         'buckets older than an hour are pruned';

  assert not has_table_privilege('authenticated', 'public.ai_rate_buckets', 'select'), 'client can read buckets';
  assert not has_function_privilege('authenticated', 'public.reserve_quota(uuid,text)', 'execute'), 'client can reserve';

  raise exception 'ALL_TESTS_PASSED';
end $$;
