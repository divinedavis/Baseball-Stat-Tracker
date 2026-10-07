-- Always rolls back (final RAISE 'ALL_TESTS_PASSED').
do $$
declare
  t text;
begin
  -- anon may read exactly the public tables we intend, nothing else
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r','v','m','p') loop
    if t = 'tier_limits' then
      assert has_table_privilege('anon', 'public.' || t, 'select'), 'anon must read tier_limits';
    else
      assert not has_table_privilege('anon', 'public.' || t, 'select'), format('anon can SELECT %s', t);
    end if;
    assert not has_table_privilege('anon', 'public.' || t, 'insert,update,delete,truncate'),
           format('anon can write %s', t);
  end loop;

  -- signed-in clients keep what the app uses
  assert has_table_privilege('authenticated', 'public.subscriptions', 'select'), 'app reads subscriptions';
  assert has_table_privilege('authenticated', 'public.app_events', 'insert'), 'app inserts app_events';

  -- a table created from now on does not hand anon SELECT
  create table public.__grant_probe (id int);
  assert not has_table_privilege('anon', 'public.__grant_probe', 'select'), 'default privileges still grant anon SELECT';

  raise exception 'ALL_TESTS_PASSED';
end $$;
