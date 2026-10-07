-- Runs in one transaction and ALWAYS rolls back: success is signalled by the
-- final RAISE 'ALL_TESTS_PASSED' (scripts/run_sql_tests.py expects it).
do $$
declare
  u uuid := gen_random_uuid();
  t ai_tier;
begin
  insert into auth.users (id, email, aud, role) values (u, u || '@test.invalid', 'authenticated', 'authenticated');

  -- no row -> free
  assert public.effective_tier(u) = 'free', 'no subscription should be free';

  -- sandbox pro, not allowlisted, window closed -> free
  update public.billing_settings set sandbox_grants_open_until = null;
  insert into public.subscriptions (user_id, tier, environment, expires_at)
       values (u, 'pro', 'Sandbox', now() + interval '1 day');
  assert public.effective_tier(u) = 'free', 'sandbox pro must not unlock pro';
  select q.tier into t from public.check_quota(u, 'question') q;
  assert t = 'free', 'check_quota must report free for sandbox pro';

  -- review window open -> pro
  update public.billing_settings set sandbox_grants_open_until = now() + interval '1 day';
  assert public.effective_tier(u) = 'pro', 'open review window should honour sandbox';
  update public.billing_settings set sandbox_grants_open_until = now() - interval '1 minute';
  assert public.effective_tier(u) = 'free', 'expired review window must not honour sandbox';

  -- allowlisted -> pro
  insert into public.sandbox_tier_allowlist (user_id, note) values (u, 'test');
  assert public.effective_tier(u) = 'pro', 'allowlisted sandbox user keeps pro';
  delete from public.sandbox_tier_allowlist where user_id = u;

  -- production -> pro; manual (null env) -> pro; expired production -> free
  update public.subscriptions set environment = 'Production' where user_id = u;
  assert public.effective_tier(u) = 'pro', 'production pro is pro';
  update public.subscriptions set environment = null where user_id = u;
  assert public.effective_tier(u) = 'pro', 'manual grant (null env) is pro';
  update public.subscriptions set environment = 'Production', expires_at = now() - interval '1 second' where user_id = u;
  assert public.effective_tier(u) = 'free', 'expired production is free';

  -- the three owner/test accounts still resolve to pro
  assert (select count(*) from public.subscriptions s
           where s.expires_at > '2099-01-01' and public.effective_tier(s.user_id) = 'pro') >= 3,
         'owner 2099 grants must stay pro';

  -- client roles cannot read the gate tables
  assert not has_table_privilege('anon', 'public.sandbox_tier_allowlist', 'select'), 'anon reads allowlist';
  assert not has_table_privilege('authenticated', 'public.billing_settings', 'select'), 'authenticated reads settings';
  assert not has_function_privilege('authenticated', 'public.effective_tier(uuid)', 'execute'), 'authenticated runs effective_tier';

  raise exception 'ALL_TESTS_PASSED';
end $$;
