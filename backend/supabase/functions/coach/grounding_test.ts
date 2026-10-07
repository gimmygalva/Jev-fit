import { assert, assertEquals } from "jsr:@std/assert@1";
import { parseDraft, parseRequest, systemPrompt, userPrompt, validateDraft } from "./grounding.ts";

const fact = { id: "proposed_target_kcal", label: "Target proposto", value: 2350, unit: "kcal", formatted: "2350 kcal" };

Deno.test("richiesta valida e limiti", () => {
  const ok = parseRequest({ tier: "routine", purpose: "today_card", facts: [fact], reasonCodes: ["checkin.training.keep"] });
  assert(ok);
  assertEquals(ok.userMessage, null);
  assertEquals(parseRequest({ tier: "x", purpose: "a", facts: [], reasonCodes: [] }), null);
  assertEquals(parseRequest({ tier: "routine", purpose: "Bad Purpose", facts: [], reasonCodes: [] }), null);
  assertEquals(parseRequest({ tier: "routine", purpose: "a", facts: [{ ...fact, id: "DROP TABLE" }], reasonCodes: [] }), null);
  assertEquals(parseRequest({ tier: "routine", purpose: "a", facts: [{ ...fact, value: Infinity }], reasonCodes: [] }), null);
  assertEquals(parseRequest({ tier: "routine", purpose: "a", facts: [], reasonCodes: [], userMessage: "x".repeat(1001) }), null);
  assertEquals(parseRequest(null), null);
});

Deno.test("il prompt non contiene i valori dei fatti", () => {
  const request = parseRequest({ tier: "analysis", purpose: "check_in_explanation", facts: [fact], reasonCodes: [] })!;
  const prompt = userPrompt(request);
  assert(prompt.includes("proposed_target_kcal"));
  assert(!prompt.includes("2350"));
  assert(systemPrompt().includes("{{fact:ID}}"));
});

Deno.test("parsing della risposta del modello", () => {
  const draft = parseDraft('Ecco: {"headline": "Su", "body": "Target {{fact:proposed_target_kcal}}", "why": [], "dataUsed": ["proposed_target_kcal"]}');
  assert(draft);
  assertEquals(validateDraft(draft, [fact]), []);
  assertEquals(parseDraft("niente json"), null);
  assertEquals(parseDraft('{"headline": 3}'), null);
});

Deno.test("grounding: cifre, numeri in lettere, segnaposto e contenuti vietati", () => {
  const base = { headline: "Ok", body: "", why: [], dataUsed: [] };
  assertEquals(validateDraft({ ...base, body: "Mangia 2500 kcal" }, [fact]), ["literal_digits"]);
  assertEquals(validateDraft({ ...base, body: "Mangia duemila kcal" }, [fact]), ["number_word:duemila"]);
  assertEquals(validateDraft({ ...base, body: "{{fact:ghost}}" }, [fact]), ["unknown_fact:ghost"]);
  assertEquals(validateDraft({ ...base, body: "Fai un digiuno" }, [fact]), ["disallowed:digiun"]);
  assertEquals(validateDraft({ ...base, dataUsed: ["ghost"] }, [fact]), ["unknown_data_used:ghost"]);
  assertEquals(validateDraft({ headline: " ", body: "", why: [], dataUsed: [] }, []), ["empty"]);
  assertEquals(validateDraft({ ...base, body: "Sei sulla buona strada, una settimana solida." }, []), []);
});
