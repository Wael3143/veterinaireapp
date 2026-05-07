const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.0-flash";

function json(data: unknown) {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" });

  try {
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiApiKey) return json({ error: "GEMINI_API_KEY not configured in Supabase secrets." });

    // Optional: verify user auth (remove if you want unauthenticated access)
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const authHeader = req.headers.get("Authorization");

    if (supabaseUrl && supabaseAnonKey && authHeader?.startsWith("Bearer ")) {
      const { createClient } = await import("npm:@supabase/supabase-js@2");
      const token = authHeader.replace("Bearer ", "").trim();
      const supabase = createClient(supabaseUrl, supabaseAnonKey);
      const { error: userError } = await supabase.auth.getUser(token);
      if (userError) return json({ error: "Session expiree, reconnectez-vous" });
    }

    const body = await req.json().catch(() => null);
    if (!body) return json({ error: "Invalid request body" });

    const messages: Array<{ role: string; content: string }> = Array.isArray(body.messages) ? body.messages : [];
    const maxTokens = Number.isFinite(body.max_tokens) ? body.max_tokens : 2048;
    const temperature = Number.isFinite(body.temperature) ? body.temperature : 0.35;

    if (!messages.length) return json({ error: "Aucun message envoye" });

    // Extract system message if present
    const systemMsg = messages.find(m => m.role === "system");
    const chatMessages = messages.filter(m => m.role !== "system");

    // Convert OpenAI-style messages to Gemini format
    const contents = chatMessages.map(m => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.content }],
    }));

    // Build Gemini request
    const geminiBody: Record<string, unknown> = {
      contents,
      generationConfig: { temperature, maxOutputTokens: maxTokens },
    };
    if (systemMsg) {
      geminiBody.systemInstruction = { parts: [{ text: systemMsg.content }] };
    }

    const model = typeof body.model === "string" && body.model.startsWith("gemini") ? body.model : GEMINI_MODEL;
    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiApiKey}`;

    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(geminiBody),
    });

    const data = await res.json().catch(() => null);

    if (!res.ok) {
      return json({
        error: data?.error?.message ?? `Gemini API error (${res.status})`,
        status: res.status,
      });
    }

    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    if (!text) {
      return json({ error: "Reponse vide du modele", details: data });
    }

    // Return in same format the frontend expects
    return json({
      model,
      content: text,
      choices: [{ message: { role: "assistant", content: text } }],
      usage: data?.usageMetadata ?? null,
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected server error" });
  }
});
