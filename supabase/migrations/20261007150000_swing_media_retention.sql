-- Swing media retention: 30 days max (most is deleted within seconds).
--
-- PRIVACY.md used to say swing photos/videos (usually of children) were
-- kept until account deletion. ai-analyze-swing now deletes the media when
-- each request finishes; this daily job removes anything older than 30 days
-- that never reached it, via the swing-media-sweep edge function (storage
-- objects can only be deleted through the Storage API).
--
-- Out-of-band, NOT in this file (secret):
--   supabase secrets set SWEEP_SECRET=<random 64 hex>   (function env)
--   select vault.create_secret('<same value>', 'swing_media_sweep_secret');
--
-- Idempotent: safe to re-run.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Names of swing-media objects older than p_days, oldest first.
create or replace function public.swing_media_expired(p_days int, p_limit int default 500)
returns table (name text)
language sql
stable
security definer
set search_path = ''
as $$
  select o.name
    from storage.objects o
   where o.bucket_id = 'swing-media'
     and o.created_at < now() - make_interval(days => greatest(p_days, 1))
   order by o.created_at
   limit least(greatest(p_limit, 1), 1000);
$$;
revoke all on function public.swing_media_expired(int, int) from public, anon, authenticated;
grant execute on function public.swing_media_expired(int, int) to service_role;

-- Keep pg_net's response log small (see pg_net disk-IO incidents on other
-- projects); this job posts once a day so an hour of history is plenty.
select cron.unschedule(jobid) from cron.job
 where jobname in ('swing-media-sweep', 'pg-net-response-retention');

select cron.schedule(
  'swing-media-sweep',
  '17 4 * * *',
  $job$
  select net.http_post(
    url := 'https://ifcsanqnrbefgsydcfgf.supabase.co/functions/v1/swing-media-sweep',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-sweep-secret', (select decrypted_secret from vault.decrypted_secrets
                          where name = 'swing_media_sweep_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $job$
);

select cron.schedule(
  'pg-net-response-retention',
  '*/30 * * * *',
  $job$ delete from net._http_response where created < now() - interval '1 hour' $job$
);
