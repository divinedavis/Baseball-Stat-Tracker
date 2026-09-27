-- Trim the Data API table grants to what the app actually does.
--
-- migrations/001_explicit_grants.sql (and Supabase's stock default
-- privileges) gave `authenticated` SELECT/INSERT/UPDATE/DELETE plus
-- TRUNCATE/TRIGGER/REFERENCES on every public table. RLS already refuses the
-- writes — none of these tables has a client write policy except the
-- app_events INSERT — so nothing is exploitable today. But the grant layer is
-- the second line: if a future migration ever adds a loose policy (or turns
-- RLS off while debugging), `subscriptions` and the quota tables would become
-- writable by any signed-in user, i.e. free Pro tier / unlimited AI calls.
-- TRUNCATE is worse: RLS never runs for it at all.
--
-- What the iOS client really touches (audited 2026-09-27):
--   subscriptions  SELECT (BillingStore.fetchServerTier)
--   app_events     INSERT (EventLogger), SELECT via owner policy
-- Everything else (chat_messages, swing_analyses, usage_counters,
-- daily_usage, tier_limits writes) is done by edge functions with the
-- service-role key, which is untouched here.
--
-- SELECT stays granted everywhere so an anon/expired-session read returns
-- 0 rows through RLS rather than a hard 42501.
--
-- Idempotent: safe to re-run.

revoke truncate, trigger, references on all tables in schema public
  from anon, authenticated;
revoke insert, update, delete on all tables in schema public from anon;

revoke insert, update, delete on
  public.subscriptions,
  public.usage_counters,
  public.daily_usage,
  public.tier_limits,
  public.swing_analyses,
  public.chat_messages
  from authenticated;
revoke update, delete on public.app_events from authenticated;

-- Keep future tables from re-acquiring the same grants.
alter default privileges in schema public
  revoke insert, update, delete, truncate, trigger, references on tables from anon;
alter default privileges in schema public
  revoke truncate, trigger, references on tables from authenticated;
alter default privileges for role postgres in schema public
  revoke insert, update, delete, truncate, trigger, references on tables from anon;
alter default privileges for role postgres in schema public
  revoke truncate, trigger, references on tables from authenticated;
