// POST /functions/v1/ai-analyze-swing
// Body (JSON): { storage_path: string, media_kind: "photo" | "video", note?: string }
//
// The iOS app uploads the media directly to the `swing-media` bucket using the
// authenticated user's session, then calls this function with the storage path.
// We download the media via the service-role client, call Claude vision, write
// the analysis to `swing_analyses`, increment quota counters, and return the
// feedback.

import "@supabase/functions-js/edge-runtime.d.ts";
import { requireUser, jsonError } from "../_shared/auth.ts";
import { callClaude, type ContentBlock } from "../_shared/anthropic.ts";
import { corsHeaders } from "../_shared/cors.ts";

const SYSTEM_PROMPT = `You are Barrel, an expert baseball hitting coach with 25+ years of experience working with players from Little League through MLB. You analyze a single swing photo or short video and return concrete, actionable feedback in this structure:

1. **What you did well** — 1-3 specific positives, with the body part / phase where you saw them.
2. **Top thing to fix** — the single highest-leverage adjustment, framed as one drill cue (a sentence the player can repeat to themselves in the box).
3. **Why it matters** — one sentence connecting the cue to outcomes (exit velo, contact quality, plate coverage).
4. **Drill to try** — one specific drill, 5-10 reps, that targets the fix.

Stay specific to what is visible in the media. If the media is unclear, say so and ask one targeted clarifying question. Never invent details you cannot see.`;

const MODEL = "claude-sonnet-4-6";
const MAX_VIDEO_FRAMES = 8; // sample at most 8 frames from a video clip
const MAX_TOKENS = 1024;

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

  let payload: { storage_path?: string; media_kind?: string; note?: string };
  try {
    payload = await req.json();
  } catch {
    return jsonError(400, "invalid json");
  }

  const { storage_path, media_kind, note } = payload;
  if (!storage_path || !media_kind) return jsonError(400, "storage_path and media_kind required");
  if (!["photo", "video"].includes(media_kind)) return jsonError(400, "media_kind must be photo|video");
  if (!storage_path.startsWith(`${userId}/`)) return jsonError(403, "path does not belong to user");

  // Quota check before doing any expensive work.
  const { data: quota, error: quotaErr } = await service.rpc("check_quota", {
    p_user: userId,
    p_kind: "swing",
  });
  if (quotaErr || !quota || !quota[0]) return jsonError(500, "quota check failed");
  const q = quota[0];
  if (!q.allowed) {
    return new Response(
      JSON.stringify({
        error: "quota_exceeded",
        reason: q.reason,
        tier: q.tier,
        monthly_remaining: q.monthly_remaining,
        daily_remaining: q.daily_remaining,
      }),
      { status: 402, headers: { "content-type": "application/json" } },
    );
  }

  // Download the media from storage.
  const { data: file, error: dlErr } = await service.storage
    .from("swing-media")
    .download(storage_path);
  if (dlErr || !file) return jsonError(404, "media not found");

  const mimeType = file.type || (media_kind === "video" ? "video/mp4" : "image/jpeg");

  let imageBlocks: ContentBlock[];

  if (media_kind === "photo") {
    const buf = new Uint8Array(await file.arrayBuffer());
    imageBlocks = [
      {
        type: "image",
        source: { type: "base64", media_type: mimeType, data: base64(buf) },
      },
    ];
  } else {
    // For video: Claude's vision API takes images, not video. We trust the
    // iOS app to extract a small number of representative frames (uniformly
    // sampled across the clip) and upload them as a multipart bundle, OR
    // we accept a single keyframe in v1. For now: treat the uploaded asset
    // as the cover frame and ask the user to upload more frames from the
    // app side later. Keeps v1 shippable.
    const buf = new Uint8Array(await file.arrayBuffer());
    imageBlocks = [
      {
        type: "image",
        source: {
          type: "base64",
          media_type: "image/jpeg",
          data: base64(buf),
        },
      },
    ];
  }

  // Cache the system prompt so repeat analyses cost less.
  const systemBlocks: ContentBlock[] = [
    { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
  ];

  const userText = note?.trim()
    ? `Player note: ${note.trim()}\n\nAnalyze the swing.`
    : "Analyze the swing.";

  const claude = await callClaude({
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system: systemBlocks,
    messages: [
      {
        role: "user",
        content: [...imageBlocks, { type: "text", text: userText }],
      },
    ],
  });

  const feedback = claude.content
    .filter((c) => c.type === "text")
    .map((c) => c.text)
    .join("\n\n");

  // Persist the analysis + bump usage counters.
  const { data: row, error: insertErr } = await service
    .from("swing_analyses")
    .insert({
      user_id: userId,
      storage_path,
      media_kind,
      feedback,
      model: claude.model,
      input_tokens: claude.usage.input_tokens,
      output_tokens: claude.usage.output_tokens,
    })
    .select()
    .single();

  if (insertErr) return jsonError(500, "failed to save analysis", { detail: insertErr.message });

  await service.rpc("increment_usage", { p_user: userId, p_kind: "swing" });

  return new Response(
    JSON.stringify({
      id: row.id,
      feedback,
      tier: q.tier,
      monthly_remaining: q.monthly_remaining - 1,
      daily_remaining: q.daily_remaining - 1,
    }),
    { headers: { "content-type": "application/json", ...corsHeaders } },
  );
});

function base64(buf: Uint8Array): string {
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < buf.length; i += chunk) {
    bin += String.fromCharCode(...buf.subarray(i, i + chunk));
  }
  return btoa(bin);
}
