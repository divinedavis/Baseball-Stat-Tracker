-- Take EXECUTE on the quota functions away from anon and authenticated.
--
-- 20260505202803 revoked them "from public" and granted only service_role,
-- which reads like it closes the door but does not. Supabase ships
-- ALTER DEFAULT PRIVILEGES granting EXECUTE on new functions in the public
-- schema to anon and authenticated, so those two roles hold their own grant
-- rather than reaching the function through PUBLIC. Revoking PUBLIC leaves
-- both grants in place; the roles have to be named.
--
-- It matters here because both functions take the target user as a parameter
-- and never check it against the caller:
--
--   check_quota(p_user uuid, p_kind text)
--   increment_usage(p_user uuid, p_kind text)
--
-- They are SECURITY DEFINER, so they bypass RLS. Any client holding the anon
-- key — which ships inside the app — could call increment_usage() against
-- another user's id and burn through the AI swing/chat allowance that user is
-- paying for, or call check_quota() to probe someone else's remaining balance.
-- Only the edge functions (ai-analyze-swing, ai-chat) are meant to call these,
-- and they use the service-role key.
--
-- Idempotent: safe to re-run.

revoke all on function public.check_quota(uuid, text)
    from public, anon, authenticated;
revoke all on function public.increment_usage(uuid, text)
    from public, anon, authenticated;

grant execute on function public.check_quota(uuid, text) to service_role;
grant execute on function public.increment_usage(uuid, text) to service_role;
