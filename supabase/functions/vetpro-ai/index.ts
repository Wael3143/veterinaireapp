import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const DEFAULT_MODEL = Deno.env.get("OPENROUTER_MODEL") ?? "meta-llama/llama-3.3-70b-instruct:free";
const APP_NAME = Deno.env.get("OPENROUTER_APP_NAME") ?? "VetPro";
const SITE_URL = Deno.env.get("OPENROUTER_SITE_URL") ?? "http://localhost:3000";

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const openRouterApiKey = Deno.env.get("OPENROUTER_API_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const authHeader = req.headers.get("Authorization");

    if (!openRouterApiKey) {
      return json({ error: "Missing OPENROUTER_API_KEY secret" }, 500);
    }

    if (!supabaseUrl || !supabaseAnonKey) {
      return json({ error: "Missing Supabase environment" }, 500);
    }

    if (!authHeader?.startsWith("Bearer ")) {
      return json({ error: "Missing Authorization header" }, 401);
    }

    const token = authHeader.replace("Bearer ", "").trim();
    const supabase = createClient(supabaseUrl, supabaseAnonKey);
    const { data: userData, error: userError } = await supabase.auth.getUser(token);

    if (userError || !userData?.user?.email) {
      return json({ error: "Unauthorized" }, 401);
    }

    const body = await req.json().catch(() => null);
    const messages = Array.isArray(body?.messages) ? body.messages : [];
    const model = typeof body?.model === "string" ? body.model : DEFAULT_MODEL;
    const max_tokens = Number.isFinite(body?.max_tokens) ? body.max_tokens : 1024;
    const temperature = Number.isFinite(body?.temperature) ? body.temperature : 0.35;

    if (!messages.length) {
      return json({ error: "Missing messages" }, 400);
    }

    const upstream = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openRouterApiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": SITE_URL,
        "X-OpenRouter-Title": APP_NAME,
      },
      body: JSON.stringify({
        model,
        messages,
        max_tokens,
        temperature,
      }),
    });

    const payload = await upstream.json().catch(() => null);

    if (!upstream.ok) {
      return json(
        {
          error: payload?.error?.message ?? "OpenRouter request failed",
          details: payload,
        },
        upstream.status,
      );
    }

    return json({
      model: payload?.model ?? model,
      usage: payload?.usage ?? null,
      content: payload?.choices?.[0]?.message?.content ?? "",
      choices: payload?.choices ?? [],
    });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : "Unexpected server error" },
      500,
    );
  }
});
