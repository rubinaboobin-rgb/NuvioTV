import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
  const user = userResult.user;
  if (userError || !user || user.is_anonymous) {
    return jsonResponse({ error: "A full signed-in account is required" }, 401);
  }

  const body = await req.json().catch(() => ({}));
  const code = String(body.code ?? "").trim().toUpperCase();
  const accessToken = String(body.access_token ?? bearer).trim();
  const refreshToken = String(body.refresh_token ?? "").trim();
  const tokenType = String(body.token_type ?? "bearer").trim() || "bearer";
  const expiresIn = Number.isFinite(Number(body.expires_in)) ? Number(body.expires_in) : null;

  if (!code || !refreshToken) {
    return jsonResponse({ error: "Missing code or refresh_token" }, 400);
  }

  const { data: loginSession, error: sessionError } = await admin
    .from("tv_login_sessions")
    .select("code, status, expires_at")
    .eq("code", code)
    .eq("status", "pending")
    .gt("expires_at", new Date().toISOString())
    .single();

  if (sessionError || !loginSession) {
    return jsonResponse({ error: "TV login session is invalid or expired" }, 404);
  }

  const { error: updateError } = await admin
    .from("tv_login_sessions")
    .update({
      status: "approved",
      approved_user_id: user.id,
      approved_access_token: accessToken,
      approved_refresh_token: refreshToken,
      token_type: tokenType,
      expires_in: expiresIn,
      approved_at: new Date().toISOString(),
    })
    .eq("code", code);

  if (updateError) {
    return jsonResponse({ error: updateError.message }, 500);
  }

  return jsonResponse({ success: true });
});
