// POST /functions/v1/ai-chat
// Body: { message: string, swing_id?: string }
//
// Free-form Q&A about hitting. If `swing_id` is supplied, the prior swing
// analysis is included as context so the user can ask follow-ups about a
// specific swing they uploaded.

import "@supabase/functions-js/edge-runtime.d.ts";
import { requireUser, jsonError } from "../_shared/auth.ts";
import { callClaude, type ContentBlock, type Message } from "../_shared/anthropic.ts";
import { corsHeaders } from "../_shared/cors.ts";

const SYSTEM_PROMPT = `You are Barrel, a friendly expert baseball hitting coach. Answer the player's question in 2-4 short paragraphs. Use plain language a 12-year-old could follow, but don't dumb down the mechanics. If the question is off-topic from baseball/hitting, redirect politely.`;

const MODEL = "claude-haiku-4-5-20251001";
const MAX_TOKENS = 800;
const HISTORY_LIMIT = 10;

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

  const { message, swing_id } = await req.json().catch(() => ({}));
  if (!message || typeof message !== "string") return jsonError(400, "message required");

  const { data: quota, error: quotaErr } = await service.rpc("check_quota", {
    p_user: userId,
    p_kind: "question",
  });
  if (quotaErr || !quota?.[0]) return jsonError(500, "quota check failed");
  const q = quota[0];
  if (!q.allowed) {
    return new Response(
      JSON.stringify({
        error: "quota_exceeded",
        reason: q.reason,
        tier: q.tier,
        monthly_remaining: q.monthly_remaining,
      }),
      { status: 402, headers: { "content-type": "application/json" } },
    );
  }

  const { data: history } = await service
    .from("chat_messages")
    .select("role, content")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(HISTORY_LIMIT);

  const orderedHistory = (history ?? []).reverse() as Message[];

  let preamble = "";
  if (swing_id) {
    const { data: swing } = await service
      .from("swing_analyses")
      .select("feedback, created_at")
      .eq("user_id", userId)
      .eq("id", swing_id)
      .single();
    if (swing?.feedback) {
      preamble = `Context — your most recent swing analysis:\n${swing.feedback}\n\n`;
    }
  }

  const systemBlocks: ContentBlock[] = [
    { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
  ];

  const userMessage: Message = { role: "user", content: preamble + message };

  const claude = await callClaude({
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system: systemBlocks,
    messages: [...orderedHistory, userMessage],
  });

  const reply = claude.content
    .filter((c) => c.type === "text")
    .map((c) => c.text)
    .join("\n\n");

  await service.from("chat_messages").insert([
    { user_id: userId, role: "user", content: message, swing_id: swing_id ?? null },
    { user_id: userId, role: "assistant", content: reply, swing_id: swing_id ?? null },
  ]);

  await service.rpc("increment_usage", { p_user: userId, p_kind: "question" });

  return new Response(
    JSON.stringify({
      reply,
      tier: q.tier,
      monthly_remaining: q.monthly_remaining < 0 ? -1 : q.monthly_remaining - 1,
    }),
    { headers: { "content-type": "application/json", ...corsHeaders } },
  );
});
