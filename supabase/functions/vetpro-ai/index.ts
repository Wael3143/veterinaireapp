import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const PRIMARY_MODEL = Deno.env.get("OPENROUTER_MODEL") ?? "meta-llama/llama-3.3-70b-instruct:free";
const FALLBACK_MODELS = (Deno.env.get("OPENROUTER_FALLBACK_MODELS") ?? [
  "meta-llama/llama-3.3-70b-instruct:free",
  "google/gemini-2.0-flash-exp:free",
  "meta-llama/llama-3.2-3b-instruct:free",
  "qwen/qwen-2.5-72b-instruct:free",
  "mistralai/mistral-7b-instruct:free",
].join(",")).split(",").map(s => s.trim()).filter(Boolean);
const APP_NAME = Deno.env.get("OPENROUTER_APP_NAME") ?? "VetPro";
const SITE_URL = Deno.env.get("OPENROUTER_SITE_URL") ?? "https://vetpro.dz";

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function callOpenRouter(apiKey: string, model: string, messages: unknown, max_tokens: number, temperature: number) {
  const res = await fetch(OPENROUTER_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": SITE_URL,
      "X-Title": APP_NAME,
    },
    body: JSON.stringify({ model, messages, max_tokens, temperature }),
  });
  const payload = await res.json().catch(() => null);
  return { res, payload };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const openRouterApiKey = Deno.env.get("OPENROUTER_API_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const authHeader = req.headers.get("Authorization");

    if (!openRouterApiKey) return json({ error: "Missing OPENROUTER_API_KEY secret" }, 500);
    if (!supabaseUrl || !supabaseAnonKey) return json({ error: "Missing Supabase environment" }, 500);
    if (!authHeader?.startsWith("Bearer ")) return json({ error: "Missing Authorization header" }, 401);

    const token = authHeader.replace("Bearer ", "").trim();
    const supabase = createClient(supabaseUrl, supabaseAnonKey);
    const { data: userData, error: userError } = await supabase.auth.getUser(token);
    if (userError || !userData?.user?.email) return json({ error: "Unauthorized" }, 401);

    const body = await req.json().catch(() => null);
    const messages = Array.isArray(body?.messages) ? body.messages : [];
    const requestedModel = typeof body?.model === "string" ? body.model : PRIMARY_MODEL;
    const max_tokens = Number.isFinite(body?.max_tokens) ? body.max_tokens : 1024;
    const temperature = Number.isFinite(body?.temperature) ? body.temperature : 0.35;

    if (!messages.length) return json({ error: "Missing messages" }, 400);

    const tried: string[] = [];
    const candidates = [requestedModel, ...FALLBACK_MODELS.filter(m => m !== requestedModel)];

    let lastError: { status: number; message: string; details?: unknown } | null = null;

    for (const model of candidates) {
      tried.push(model);
      const { res, payload } = await callOpenRouter(openRouterApiKey, model, messages, max_tokens, temperature);

      if (res.ok && payload?.choices?.[0]?.message?.content) {
        return json({
          model: payload?.model ?? model,
          usage: payload?.usage ?? null,
          content: payload.choices[0].message.content,
          choices: payload.choices,
          tried,
        });
      }

      lastError = {
        status: res.status,
        message: payload?.error?.message ?? `OpenRouter ${res.status}`,
        details: payload,
      };

      const retryable = res.status === 429 || res.status === 502 || res.status === 503 || res.status === 504;
      if (!retryable) break;
    }

    return json(
      {
        error: lastError?.message ?? "OpenRouter request failed",
        status: lastError?.status ?? 500,
        tried,
        hint: lastError?.status === 429
          ? "Tous les modèles gratuits OpenRouter sont saturés (rate limit). Réessayez dans quelques minutes ou ajoutez du crédit OpenRouter."
          : undefined,
        details: lastError?.details,
      },
      lastError?.status ?? 500,
    );
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : "Unexpected server error" },
      500,
    );
  }
});
