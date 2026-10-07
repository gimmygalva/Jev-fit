/** Il client deve inviare `{"confirm": "DELETE"}`: una richiesta accidentale non elimina nulla. */
export function isConfirmed(body: unknown): boolean {
  return typeof body === "object" && body !== null && (body as Record<string, unknown>).confirm === "DELETE";
}
