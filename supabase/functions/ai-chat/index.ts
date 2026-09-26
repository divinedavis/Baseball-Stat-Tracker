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
// Input caps: the paid Claude call must not accept unbounded text.
const MAX_MESSAGE_CHARS = 2000;
const MAX_HISTORY_ITEM_CHARS = 2000;
const MAX_HISTORY_TOTAL_CHARS = 12000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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
  if (!message || typeof message !== "string" || !message.trim()) {
    return jsonError(400, "message required");
  }
  if (message.length > MAX_MESSAGE_CHARS) {
    return jsonError(413, "message too long", { max_chars: MAX_MESSAGE_CHARS });
  }
  if (swing_id != null && (typeof swing_id !== "string" || !UUID_RE.test(swing_id))) {
    return jsonError(400, "invalid swing_id");
  }

  // Reserve one question atomically (check + increment in one locked
  // transaction) BEFORE the paid call, so concurrent requests can't all pass
  // the check. Refunded below if the Claude call fails.
  const { data: quota, error: quotaErr } = await service.rpc("reserve_quota", {
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

  // Newest-first: keep rows until the total budget is spent, truncating each.
  const orderedHistory: Message[] = [];
  let historyChars = 0;
  for (const row of (history ?? []) as Array<{ role: string; content: string }>) {
    if (row.role !== "user" && row.role !== "assistant") continue;
    const text = String(row.content ?? "").slice(0, MAX_HISTORY_ITEM_CHARS);
    if (historyChars + text.length > MAX_HISTORY_TOTAL_CHARS) break;
    historyChars += text.length;
    orderedHistory.unshift({ role: row.role, content: text });
  }
  // The Messages API wants the conversation to open with a user turn.
  while (orderedHistory.length && orderedHistory[0].role !== "user") orderedHistory.shift();

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

  let claude;
  try {
    claude = await callClaude({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: systemBlocks,
      messages: [...orderedHistory, userMessage],
    });
  } catch (e) {
    console.error("ai-chat claude call failed", e instanceof Error ? e.message : e);
    await service.rpc("release_quota", { p_user: userId, p_kind: "question" });
    return jsonError(502, "ai_unavailable");
  }

  const reply = claude.content
    .filter((c) => c.type === "text")
    .map((c) => c.text)
    .join("\n\n");

  await service.from("chat_messages").insert([
    { user_id: userId, role: "user", content: message, swing_id: swing_id ?? null },
    { user_id: userId, role: "assistant", content: reply, swing_id: swing_id ?? null },
  ]);

  return new Response(
    JSON.stringify({
      reply,
      tier: q.tier,
      monthly_remaining: q.monthly_remaining < 0 ? -1 : q.monthly_remaining - 1,
    }),
    { headers: { "content-type": "application/json", ...corsHeaders } },
  );
});
