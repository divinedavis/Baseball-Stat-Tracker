// POST /functions/v1/swing-media-sweep   (pg_cron, daily)
// Header: x-sweep-secret: <SWEEP_SECRET>
//
// Deletes swing-media objects older than RETENTION_DAYS. ai-analyze-swing
// already deletes media when an analysis request finishes; this catches
// uploads that never reached it (app killed mid-request, network drop) so
// no child's swing photo/video outlives the 30-day promise in PRIVACY.md.
//
// Objects must be removed through the Storage API (storage.objects has a
// delete-protection trigger), hence an edge function rather than pure SQL.
// verify_jwt is off; the shared secret (function env + Vault, used by the
// cron job) is the only way in.

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const RETENTION_DAYS = 30;
const BATCH = 500;

function timingSafeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  const secret = Deno.env.get("SWEEP_SECRET") ?? "";
  const given = req.headers.get("x-sweep-secret") ?? "";
  if (secret.length < 32 || !timingSafeEqual(given, secret)) {
    return new Response("forbidden", { status: 403 });
  }

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  let removed = 0;
  for (let round = 0; round < 20; round++) {
    const { data, error } = await sb.rpc("swing_media_expired", {
      p_days: RETENTION_DAYS,
      p_limit: BATCH,
    });
    if (error) {
      console.error("swing-media-sweep: list failed", error.message);
      return new Response(JSON.stringify({ error: "list_failed", removed }), { status: 500 });
    }
    const names = (data ?? []).map((r: { name: string }) => r.name);
    if (names.length === 0) break;
    const { error: rmErr } = await sb.storage.from("swing-media").remove(names);
    if (rmErr) {
      console.error("swing-media-sweep: remove failed", rmErr.message);
      return new Response(JSON.stringify({ error: "remove_failed", removed }), { status: 500 });
    }
    removed += names.length;
    if (names.length < BATCH) break;
  }

  console.log(`swing-media-sweep: removed ${removed}`);
  return new Response(JSON.stringify({ removed }), {
    headers: { "content-type": "application/json" },
  });
});
