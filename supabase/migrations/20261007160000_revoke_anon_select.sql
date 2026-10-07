-- anon no longer gets SELECT on user tables.
--
-- RLS (auth.uid() = user_id) already returns 0 rows to anon, so nothing
-- leaks today, but the grant is the second line of defence: one loose
-- policy (or RLS disabled while debugging) would expose every user's
-- subscriptions, chat and swing feedback to anyone holding the bundled
-- anon key. The iOS client only reads `subscriptions` and inserts
-- `app_events`, always with a signed-in session; BillingStore treats a
-- failed read as "no server tier", so an expired-session 42501 is handled.
--
-- tier_limits stays readable (public price/limit table).
-- Supersedes the "SELECT stays granted everywhere" note in 20260927120000.
--
-- Idempotent: safe to re-run.

revoke select on
  public.subscriptions,
  public.usage_counters,
  public.daily_usage,
  public.swing_analyses,
  public.chat_messages,
  public.app_events
  from anon;

grant select on public.tier_limits to anon;

-- New public tables don't get anon SELECT by default either; grant it
-- explicitly in the migration that creates a genuinely public table.
alter default privileges in schema public revoke select on tables from anon;
alter default privileges for role postgres in schema public revoke select on tables from anon;
