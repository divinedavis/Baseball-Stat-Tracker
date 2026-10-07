// POST /functions/v1/storekit-webhook
// App Store Server Notifications V2 receiver.
//
// Apple posts a `signedPayload` (JWS). We CRYPTOGRAPHICALLY VERIFY that JWS and
// the nested `signedTransactionInfo` / `signedRenewalInfo` JWS against Apple's
// pinned Root CA - G3 before trusting any field, then update the `subscriptions`
// row for the user.
//
// User identity comes from Apple's `appAccountToken`, which the iOS client sets
// at purchase time to the Supabase auth user id. If that field is missing we
// fall back to looking up by the verified `original_transaction_id`.
//
// SECURITY: the payload is unauthenticated transport — anyone can POST here
// (verify_jwt=false, as a webhook must be). The ONLY thing that makes a write
// trustworthy is the Apple JWS signature, so we reject (400) any payload whose
// signature/cert-chain does not verify against the pinned Apple root, and we
// reject (400) any payload whose verified bundleId is not ours.

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { corsHeaders } from "../_shared/cors.ts";
import { verifyAppleJWS, JWSVerificationError } from "./appleJWS.ts";

const EXPECTED_BUNDLE_ID = "com.divinedavis.BaseballStatTracker";

// Apple retries a failed delivery 5 times at 1, 12, 24, 48 and 72 hours after
// the previous attempt (~6.5 days in total). Anything signed longer ago than
// that cannot be a genuine (re)delivery and is treated as a replay.
const MAX_NOTIFICATION_AGE_MS = 8 * 24 * 60 * 60 * 1000;

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

  // 1) Verify the outer notification JWS against Apple's pinned root.
  let payload: NotificationPayload;
  try {
    payload = await verifyAppleJWS<NotificationPayload>(body.signedPayload, {
      maxAgeMs: MAX_NOTIFICATION_AGE_MS,
    });
  } catch (e) {
    if (e instanceof JWSVerificationError) {
      console.warn("storekit-webhook: rejected unverified signedPayload:", e.message);
      return new Response("invalid signature", { status: 400 });
    }
    throw e;
  }

  // ASC "Request a Test Notification" — verified above, nothing to record.
  if (payload?.notificationType === "TEST") {
    return new Response("ok", { status: 200 });
  }

  if (!payload?.data?.signedTransactionInfo) {
    return new Response("malformed payload", { status: 400 });
  }

  // 2) Verify the nested signedTransactionInfo JWS the same way before reading
  //    any transaction field. (signedRenewalInfo, when present, is verified too
  //    so a forged renewal block cannot slip through.)
  let tx: TransactionInfo;
  try {
    tx = await verifyAppleJWS<TransactionInfo>(payload.data.signedTransactionInfo);
    if (payload.data.signedRenewalInfo) {
      await verifyAppleJWS<unknown>(payload.data.signedRenewalInfo);
    }
  } catch (e) {
    if (e instanceof JWSVerificationError) {
      console.warn("storekit-webhook: rejected unverified transaction info:", e.message);
      return new Response("invalid signature", { status: 400 });
    }
    throw e;
  }

  // 3) Only trust fields that came out of a verified JWS. Pin the bundleId so a
  //    validly-Apple-signed notification for some *other* app can't touch our
  //    subscriptions table.
  const bundleId = tx.bundleId ?? payload.data.bundleId;
  if (bundleId !== EXPECTED_BUNDLE_ID) {
    console.warn("storekit-webhook: bundleId mismatch:", bundleId);
    return new Response("bundle mismatch", { status: 400 });
  }

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

  // 4) Resolve identity. Prefer mapping the *verified* originalTransactionId to
  //    a known subscription row; only trust appAccountToken when we have no
  //    existing mapping for this original transaction.
  let userId: string | null = null;
  if (tx.originalTransactionId) {
    const { data } = await sb
      .from("subscriptions")
      .select("user_id")
      .eq("original_transaction_id", tx.originalTransactionId)
      .maybeSingle();
    userId = data?.user_id ?? null;
  }
  if (!userId && tx.appAccountToken) {
    userId = tx.appAccountToken;
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
  signedDate?: number;
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
  bundleId?: string;
  productId: string;
  originalTransactionId: string;
  appAccountToken?: string;
  expiresDate?: number;
  environment?: string;
};
