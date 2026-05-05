const ANTHROPIC_BASE = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

export type ContentBlock =
  | { type: "text"; text: string; cache_control?: { type: "ephemeral" } }
  | {
      type: "image";
      source: { type: "base64"; media_type: string; data: string };
    };

export type Message = { role: "user" | "assistant"; content: string | ContentBlock[] };

export type ClaudeRequest = {
  model: string;
  max_tokens: number;
  system?: string | ContentBlock[];
  messages: Message[];
  temperature?: number;
};

export type ClaudeUsage = {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
};

export type ClaudeResponse = {
  id: string;
  content: Array<{ type: "text"; text: string }>;
  model: string;
  stop_reason: string;
  usage: ClaudeUsage;
};

export async function callClaude(body: ClaudeRequest): Promise<ClaudeResponse> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not configured");

  const res = await fetch(ANTHROPIC_BASE, {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Anthropic API ${res.status}: ${text}`);
  }
  return await res.json();
}
