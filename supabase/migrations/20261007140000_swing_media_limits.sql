-- Shrink the swing-media bucket to what the analyzer accepts, and cap how
-- many objects one user can hold.
--
-- The bucket allowed 60 MB per object while ai-analyze-swing refuses
-- anything over 5 MB (Anthropic's image limit), so a user could park large
-- videos of (usually) children that we'd never analyze, and the only bound
-- on storage was the 1 GB project quota. Now:
--   * file_size_limit 5 MB — matches MAX_MEDIA_BYTES in ai-analyze-swing;
--     anything larger already failed analysis, now it fails at upload.
--   * the owner-insert policy also requires the user to hold fewer than
--     MAX (20) objects in the bucket. ai-analyze-swing deletes media after
--     analysis and a daily sweep removes leftovers after 30 days, so a
--     normal user holds 0-1.
--
-- Idempotent: safe to re-run.

update storage.buckets
   set file_size_limit = 5 * 1024 * 1024
 where id = 'swing-media';

-- SECURITY DEFINER so the count isn't itself filtered by the caller's RLS
-- (and can't recurse into the policy below).
create or replace function public.swing_media_object_count(p_user uuid)
returns int
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int
    from storage.objects o
   where o.bucket_id = 'swing-media'
     and (storage.foldername(o.name))[1] = p_user::text;
$$;
revoke all on function public.swing_media_object_count(uuid) from public, anon;
grant execute on function public.swing_media_object_count(uuid) to authenticated, service_role;

drop policy if exists "swing_media_owner_insert" on storage.objects;
create policy "swing_media_owner_insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'swing-media'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.swing_media_object_count(auth.uid()) < 20
  );
