// JEV gateway (M11, ADR-007): verifica l'utente, il consenso `ai_online`, sceglie il modello per
// tier (variabili d'ambiente, nessun ID nel client), chiama il provider e valida la risposta.
// Non registra mai contenuti delle richieste né delle risposte.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { type CoachDraft, type CoachRequest, parseDraft, parseRequest, systemPrompt, userPrompt, validateDraft } from "./grounding.ts";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function callAnthropic(model: string, request: CoachRequest): Promise<string> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY") ?? "",
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: 600,
      system: systemPrompt(),
      messages: [{ role: "user", content: userPrompt(request) }],
    }),
  });
  if (!response.ok) throw new Error(`provider_${response.status}`);
  const data = await response.json();
  return data?.content?.[0]?.text ?? "";
}

async function callOpenAI(model: string, request: CoachRequest): Promise<string> {
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("OPENAI_API_KEY") ?? ""}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      response_format: { type: "json_object" },
      messages: [{ role: "system", content: systemPrompt() }, { role: "user", content: userPrompt(request) }],
    }),
  });
  if (!response.ok) throw new Error(`provider_${response.status}`);
  const data = await response.json();
  return data?.choices?.[0]?.message?.content ?? "";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json(401, { error: "not_authorized" });

  const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: authorization } },
  });
  const { data: user, error: userError } = await supabase.auth.getUser();
  if (userError || !user?.user) return json(401, { error: "not_authorized" });

  // Consenso esplicito al trattamento AI online (RLS: l'utente vede solo i propri consensi).
  const { data: consent } = await supabase.from("user_consent").select("id").eq("kind", "ai_online")
    .is("revoked_at", null).limit(1);
  if (!consent || consent.length === 0) return json(403, { error: "consent_required" });

  let request: CoachRequest | null = null;
  try {
    request = parseRequest(await req.json());
  } catch {
    request = null;
  }
  if (!request) return json(400, { error: "invalid_request" });

  const provider = Deno.env.get("COACH_PROVIDER") ?? "anthropic";
  const model = Deno.env.get(request.tier === "analysis" ? "COACH_MODEL_ANALYSIS" : "COACH_MODEL_ROUTINE");
  if (!model) return json(503, { error: "unavailable" });

  let text: string;
  try {
    text = provider === "openai" ? await callOpenAI(model, request) : await callAnthropic(model, request);
  } catch (error) {
    const status = String(error).includes("provider_429") ? 429 : 502;
    return json(status, { error: status === 429 ? "rate_limited" : "unavailable" });
  }
  const draft: CoachDraft | null = parseDraft(text);
  if (!draft) return json(502, { error: "invalid_response" });
  const issues = validateDraft(draft, request.facts);
  if (issues.length > 0) return json(422, { error: "grounding_failed", issues: issues.slice(0, 10) });
  return json(200, { draft, provider, model });
});
