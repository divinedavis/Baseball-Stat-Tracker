-- swing_media_object_count(p_user) answered for ANY user id: a signed-in
-- caller could count another player's swing uploads via
-- /rest/v1/rpc/swing_media_object_count (Supabase advisor, 2026-10-12).
-- The upload policy only ever passes auth.uid(), so answer 0 for anyone
-- else unless the caller is the service role (swing-media-sweep).
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
     and (storage.foldername(o.name))[1] = p_user::text
     and (p_user = auth.uid() or auth.role() = 'service_role');
$$;
revoke all on function public.swing_media_object_count(uuid) from public, anon;
grant execute on function public.swing_media_object_count(uuid) to authenticated, service_role;
