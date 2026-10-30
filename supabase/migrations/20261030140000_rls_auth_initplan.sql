-- barrel: wrap auth.*() in (select ...) so RLS evaluates it once per
-- query, not once per row (advisor auth_rls_initplan). Same predicates.
-- Generated from live pg_policies 2026-10-30.

alter policy "subs_owner_read" on public."subscriptions"
  using ((( SELECT auth.uid() AS uid) = user_id));

alter policy "usage_owner_read" on public."usage_counters"
  using ((( SELECT auth.uid() AS uid) = user_id));

alter policy "daily_owner_read" on public."daily_usage"
  using ((( SELECT auth.uid() AS uid) = user_id));

alter policy "swings_owner_read" on public."swing_analyses"
  using ((( SELECT auth.uid() AS uid) = user_id));

alter policy "chat_owner_read" on public."chat_messages"
  using ((( SELECT auth.uid() AS uid) = user_id));

alter policy "events_owner_insert" on public."app_events"
  with check ((( SELECT auth.uid() AS uid) = user_id));

alter policy "events_owner_read" on public."app_events"
  using ((( SELECT auth.uid() AS uid) = user_id));
