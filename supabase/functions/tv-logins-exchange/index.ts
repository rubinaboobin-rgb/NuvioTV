import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "Function is not configured" }, 500);
  }

  const authorization = req.headers.get("authorization") ?? "";
  const bearer = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!bearer) {
    return jsonResponse({ error: "Missing bearer token" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userResult, error: userError } = await admin.auth.getUser(bearer);
  if (userError || !userResult.user) {
    return jsonResponse({ error: "Invalid bearer token" }, 401);
  }

  const { code, device_nonce: deviceNonce } = await req.json().catch(() => ({}));
  if (!code || !deviceNonce) {
    return jsonResponse({ error: "Missing code or device_nonce" }, 400);
  }

  const nonceHash = await sha256Hex(String(deviceNonce));
  const nowIso = new Date().toISOString();

  const { data: session, error: sessionError } = await admin
    .from("tv_login_sessions")
    .select("code, approved_access_token, approved_refresh_token, token_type, expires_in")
    .eq("code", String(code).trim().toUpperCase())
    .eq("requester_user_id", userResult.user.id)
    .eq("device_nonce_hash", nonceHash)
    .eq("status", "approved")
    .gt("expires_at", nowIso)
    .single();

  if (sessionError || !session) {
    return jsonResponse({ error: "TV login session is not approved or has expired" }, 404);
  }

  if (!session.approved_access_token || !session.approved_refresh_token) {
    return jsonResponse({ error: "Approved session has no token payload" }, 409);
  }

  await admin
    .from("tv_login_sessions")
    .update({
      status: "exchanged",
      exchanged_at: nowIso,
      approved_access_token: null,
      approved_refresh_token: null,
    })
    .eq("code", session.code);

  return jsonResponse({
    access_token: session.approved_access_token,
    refresh_token: session.approved_refresh_token,
    token_type: session.token_type ?? "bearer",
    expires_in: session.expires_in ?? null,
  });
});
