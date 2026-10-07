import { assertEquals } from "jsr:@std/assert@1";
import { isConfirmed } from "./confirm.ts";

Deno.test("serve la conferma esplicita", () => {
  assertEquals(isConfirmed({ confirm: "DELETE" }), true);
  assertEquals(isConfirmed({ confirm: "delete" }), false);
  assertEquals(isConfirmed({}), false);
  assertEquals(isConfirmed(null), false);
  assertEquals(isConfirmed("DELETE"), false);
});
