-- Private bucket for swing photos and short videos. Files are addressed by
-- `<user_id>/<uuid>.<ext>` so the storage policy can scope reads to the owner.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'swing-media',
  'swing-media',
  false,
  60 * 1024 * 1024, -- 60 MB cap (covers ~30s 1080p H.264 with headroom)
  array['image/jpeg','image/png','image/heic','video/mp4','video/quicktime']
)
on conflict (id) do update
  set file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy "swing_media_owner_read"
  on storage.objects for select
  using (bucket_id = 'swing-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "swing_media_owner_insert"
  on storage.objects for insert
  with check (bucket_id = 'swing-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "swing_media_owner_delete"
  on storage.objects for delete
  using (bucket_id = 'swing-media' and (storage.foldername(name))[1] = auth.uid()::text);
