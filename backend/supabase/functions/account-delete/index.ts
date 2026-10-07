// Eliminazione dell'account (Apple 5.1.1(v), SECURITY §7): l'utente autenticato elimina il proprio
// utente Auth; tutte le tabelle hanno `user_id ... on delete cascade`, quindi i dati nel cloud
// spariscono con lui. Richiede una conferma esplicita nel corpo. Non registra contenuti.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { isConfirmed } from "./confirm.ts";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json(401, { error: "not_authorized" });

  let body: unknown = null;
  try {
    body = await req.json();
  } catch {
    body = null;
  }
  if (!isConfirmed(body)) return json(400, { error: "confirmation_required" });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
    global: { headers: { Authorization: authorization } },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data?.user) return json(401, { error: "not_authorized" });

  // Chiave amministrativa: esiste solo nell'ambiente della funzione, mai nel client.
  const adminKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""; // secrets-scan: allow (nome della variabile, non il valore)
  if (!adminKey) return json(503, { error: "unavailable" });
  const admin = createClient(url, adminKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  if (deleteError) return json(502, { error: "delete_failed" });
  return json(200, { deleted: true });
});
