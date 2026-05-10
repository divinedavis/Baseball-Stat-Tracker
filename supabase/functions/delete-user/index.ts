// POST /functions/v1/delete-user
// No body. The user ID comes from the verified JWT.
//
// Removes the caller's swing media from Supabase Storage, then deletes the
// auth.users row. The on-delete-cascade FKs in the public schema clean up
// subscriptions, usage_counters, daily_usage, swing_analyses, chat_messages,
// and app_events automatically.
//
// Apple App Store Guideline 5.1.1(v) requires that accounts created in-app
// be deletable in-app — this function is what makes that real.

import "@supabase/functions-js/edge-runtime.d.ts";
import { requireUser, jsonError } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";

const STORAGE_BUCKET = "swing-media";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonError(405, "method not allowed");

  let ctx;
  try {
    ctx = await requireUser(req);
  } catch (r) {
    return r instanceof Response ? r : jsonError(401, "unauthorized");
  }
  const { userId, service } = ctx;

  // 1) Delete every object the user uploaded under swing-media/<userId>/
  try {
    const { data: objects, error: listErr } = await service.storage
      .from(STORAGE_BUCKET)
      .list(userId, { limit: 1000 });
    if (listErr) {
      console.error("delete-user list error", listErr);
    } else if (objects && objects.length > 0) {
      const paths = objects.map((o: { name: string }) => `${userId}/${o.name}`);
      const { error: rmErr } = await service.storage
        .from(STORAGE_BUCKET)
        .remove(paths);
      if (rmErr) console.error("delete-user remove error", rmErr);
    }
  } catch (e) {
    console.error("delete-user storage cleanup threw", e);
    // Don't abort — proceed to delete the auth user even if storage cleanup
    // partially failed. Orphan objects can be swept later; an undeletable
    // account is the worse failure mode.
  }

  // 2) Delete the auth user (cascades to public-schema FK references).
  const { error: deleteErr } = await service.auth.admin.deleteUser(userId);
  if (deleteErr) {
    console.error("delete-user admin.deleteUser error", deleteErr);
    return jsonError(500, "failed to delete account");
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
});
