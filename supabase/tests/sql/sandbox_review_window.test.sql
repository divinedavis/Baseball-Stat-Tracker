-- The statement scripts/sandbox_review_window.py runs before every App Review
-- submit (open_sql(14), copied verbatim; test_sandbox_review_window.py fails if
-- they drift). Always rolls back via the ALL_TESTS_PASSED sentinel.
do $$
declare t timestamptz;
begin
  -- never shortens a later window
  update public.billing_settings set sandbox_grants_open_until = now() + interval '20 days' where id;
  update public.billing_settings set sandbox_grants_open_until = greatest(coalesce(sandbox_grants_open_until, now()), now() + interval '14 days') where id returning sandbox_grants_open_until into t;
  assert t > now() + interval '19 days', 'shortened a later window';

  -- opens a closed window for 14 days
  update public.billing_settings set sandbox_grants_open_until = null where id;
  update public.billing_settings set sandbox_grants_open_until = greatest(coalesce(sandbox_grants_open_until, now()), now() + interval '14 days') where id returning sandbox_grants_open_until into t;
  assert t between now() + interval '13 days 23 hours' and now() + interval '14 days 1 minute', 'not 14 days';

  -- extends an expired window from now, not from the old value
  update public.billing_settings set sandbox_grants_open_until = now() - interval '3 days' where id;
  update public.billing_settings set sandbox_grants_open_until = greatest(coalesce(sandbox_grants_open_until, now()), now() + interval '14 days') where id returning sandbox_grants_open_until into t;
  assert t > now() + interval '13 days 23 hours', 'extended from the expired value';

  raise exception 'ALL_TESTS_PASSED';
end $$;
