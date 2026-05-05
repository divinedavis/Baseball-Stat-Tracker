// POST /functions/v1/storekit-webhook
// App Store Server Notifications V2 receiver.
//
// Apple posts a `signedPayload` (JWS). We decode the payload + nested
// signedTransactionInfo to update the `subscriptions` row for the user.
//
// User identity comes from Apple's `appAccountToken`, which the iOS client
// sets at purchase time to the Supabase auth user id. If that field is
// missing on a notification we fall back to looking up by
// `original_transaction_id`.

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { corsHeaders } from "../_shared/cors.ts";

const PRODUCT_TIER: Record<string, "standard" | "pro"> = {
  "com.divinedavis.BaseballStatTracker.aistandard.monthly": "standard",
  "com.divinedavis.BaseballStatTracker.aipro.monthly": "pro",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  const body = await req.json().catch(() => null);
  if (!body?.signedPayload) {
    return new Response("missing signedPayload", { status: 400 });
  }

  const payload = decodeJWSPayload<NotificationPayload>(body.signedPayload);
  if (!payload?.data?.signedTransactionInfo) {
    return new Response("malformed payload", { status: 400 });
  }
  const tx = decodeJWSPayload<TransactionInfo>(payload.data.signedTransactionInfo);
  if (!tx) return new Response("malformed transaction", { status: 400 });

  const productId = tx.productId;
  const tier = PRODUCT_TIER[productId];
  if (!tier) return new Response("ok", { status: 200 });

  const env = (payload.data.environment ?? tx.environment) === "Production"
    ? "Production"
    : "Sandbox";

  const expiresAt = tx.expiresDate ? new Date(tx.expiresDate).toISOString() : null;
  const notificationType = payload.notificationType;
  const subtype = payload.subtype;

  const ending =
    notificationType === "EXPIRED" ||
    notificationType === "REFUND" ||
    notificationType === "REVOKE" ||
    (notificationType === "DID_CHANGE_RENEWAL_STATUS" &&
      subtype === "AUTO_RENEW_DISABLED" &&
      expiresAt &&
      new Date(expiresAt) < new Date());

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const sb = createClient(url, serviceKey, { auth: { persistSession: false } });

  let userId: string | null = null;
  if (tx.appAccountToken) {
    userId = tx.appAccountToken;
  } else if (tx.originalTransactionId) {
    const { data } = await sb
      .from("subscriptions")
      .select("user_id")
      .eq("original_transaction_id", tx.originalTransactionId)
      .maybeSingle();
    userId = data?.user_id ?? null;
  }

  if (!userId) {
    console.warn("storekit-webhook: cannot resolve user for tx", tx.originalTransactionId);
    return new Response("ok", { status: 200 });
  }

  await sb.from("subscriptions").upsert(
    {
      user_id: userId,
      tier: ending ? "free" : tier,
      product_id: productId,
      original_transaction_id: tx.originalTransactionId,
      expires_at: expiresAt,
      environment: env,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id" },
  );

  return new Response("ok", { status: 200 });
});

type NotificationPayload = {
  notificationType: string;
  subtype?: string;
  data: {
    environment?: string;
    appAppleId?: number;
    bundleId?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
};

type TransactionInfo = {
  productId: string;
  originalTransactionId: string;
  appAccountToken?: string;
  expiresDate?: number;
  environment?: string;
};

function decodeJWSPayload<T>(jws: string): T | null {
  const parts = jws.split(".");
  if (parts.length !== 3) return null;
  try {
    const json = atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(json) as T;
  } catch {
    return null;
  }
}

// TODO before production: verify the JWS signature using Apple's public root
// certs per https://developer.apple.com/documentation/appstoreservernotifications/responsebodyv2
