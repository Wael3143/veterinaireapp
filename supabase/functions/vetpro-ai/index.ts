import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const PRIMARY_MODEL = Deno.env.get("OPENROUTER_MODEL") ?? "google/gemini-2.0-flash-exp:free";
const FALLBACK_MODELS = (Deno.env.get("OPENROUTER_FALLBACK_MODELS") ?? [
  "google/gemini-2.0-flash-exp:free",
  "deepseek/deepseek-r1-distill-llama-70b:free",
  "deepseek/deepseek-chat-v3-0324:free",
  "tngtech/deepseek-r1t-chimera:free",
  "qwen/qwen3-30b-a3b:free",
  "qwen/qwen-2.5-72b-instruct:free",
  "meta-llama/llama-3.3-70b-instruct:free",
  "meta-llama/llama-3.2-3b-instruct:free",
  "microsoft/mai-ds-r1:free",
  "mistralai/mistral-7b-instruct:free",
].join(",")).split(",").map(s => s.trim()).filter(Boolean);
const APP_NAME = Deno.env.get("OPENROUTER_APP_NAME") ?? "VetPro";
const SITE_URL = Deno.env.get("OPENROUTER_SITE_URL") ?? "https://vetpro.dz";

// Always 200 so the supabase-js SDK doesn't throw "non-2xx status code".
// The frontend reads `error` / `content` from the body.
function json(data: unknown, _httpStatus = 200) {
  return new Response(JSON.stringify(data), {
    status: 200,
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
    body: JSON.stringify({
      model,
      messages,
      max_tokens,
      temperature,
      // Allow OpenRouter to route to any available provider for free models
      provider: { allow_fallbacks: true, require_parameters: false },
    }),
  });
  const payload = await res.json().catch(() => null);
  return { res, payload };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" });

  try {
    const openRouterApiKey = Deno.env.get("OPENROUTER_API_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const authHeader = req.headers.get("Authorization");

    if (!openRouterApiKey) return json({ error: "Configuration manquante: OPENROUTER_API_KEY n'est pas defini dans les secrets de la fonction." });
    if (!supabaseUrl || !supabaseAnonKey) return json({ error: "Configuration Supabase manquante" });
    if (!authHeader?.startsWith("Bearer ")) return json({ error: "Authentification requise" });

    const token = authHeader.replace("Bearer ", "").trim();
    const supabase = createClient(supabaseUrl, supabaseAnonKey);
    const { data: userData, error: userError } = await supabase.auth.getUser(token);
    if (userError || !userData?.user?.email) return json({ error: "Session expiree, reconnectez-vous" });

    const body = await req.json().catch(() => null);
    const messages = Array.isArray(body?.messages) ? body.messages : [];
    const requestedModel = typeof body?.model === "string" ? body.model : PRIMARY_MODEL;
    const max_tokens = Number.isFinite(body?.max_tokens) ? body.max_tokens : 1024;
    const temperature = Number.isFinite(body?.temperature) ? body.temperature : 0.35;

    if (!messages.length) return json({ error: "Aucun message envoye" });

    const tried: string[] = [];
    const candidates = [requestedModel, ...FALLBACK_MODELS.filter(m => m !== requestedModel)];

    let lastError: { status: number; message: string; details?: unknown } | null = null;

    for (const model of candidates) {
      tried.push(model);
      try {
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
      } catch (callErr) {
        lastError = {
          status: 0,
          message: callErr instanceof Error ? callErr.message : "network error",
        };
      }
    }

    const hint = lastError?.status === 429
      ? "Tous les modeles gratuits OpenRouter sont satures. Reessayez dans 30-60 secondes ou ajoutez du credit."
      : lastError?.status === 404
      ? "Tous les modeles ont ete refuses (404). Verifiez que la cle OpenRouter est valide."
      : lastError?.status === 401 || lastError?.status === 403
      ? "Cle OpenRouter invalide ou non autorisee. Mettez a jour le secret OPENROUTER_API_KEY."
      : /provider returned error|provider error/i.test(lastError?.message || "")
      ? "Tous les fournisseurs gratuits OpenRouter sont actuellement en panne. Verifiez https://status.openrouter.ai ou ajoutez 1$ de credit pour debloquer les modeles payants."
      : "Service IA temporairement indisponible. Reessayez plus tard.";

    return json({
      error: lastError?.message ?? "OpenRouter request failed",
      status: lastError?.status ?? 500,
      tried,
      hint,
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected server error" });
  }
});
