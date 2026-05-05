import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

export type AuthedContext = {
  userId: string;
  jwt: string;
  service: SupabaseClient;
};

/**
 * Verifies the caller's JWT and returns a service-role client plus the user id.
 * Edge functions all run with the service-role key so they can bypass RLS for
 * quota updates; the user id comes from the verified JWT, not from the body.
 */
export async function requireUser(req: Request): Promise<AuthedContext> {
  const authHeader = req.headers.get("authorization") ?? "";
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new Response("Missing bearer token", { status: 401 });
  const jwt = match[1];

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) throw new Response("Invalid token", { status: 401 });

  const service = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });

  return { userId: data.user.id, jwt, service };
}

export function jsonError(status: number, message: string, extra: Record<string, unknown> = {}) {
  return new Response(JSON.stringify({ error: message, ...extra }), {
    status,
    headers: { "content-type": "application/json" },
  });
}
