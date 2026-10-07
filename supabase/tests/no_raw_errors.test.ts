// Static guard: edge functions must not send raw DB / library error text to
// clients (L2, 2026-10-07). Log it with console.error instead.
import { assertEquals } from "jsr:@std/assert@1";

Deno.test("no edge function returns error.message / detail to the client", async () => {
  const offenders: string[] = [];
  for await (const dir of Deno.readDir(new URL("../functions/", import.meta.url))) {
    if (!dir.isDirectory || dir.name.startsWith("_")) continue;
    const src = await Deno.readTextFile(new URL(`../functions/${dir.name}/index.ts`, import.meta.url));
    src.split("\n").forEach((line, i) => {
      const toClient = /jsonError\(|new Response\(/.test(line);
      if (toClient && /(\bdetail\b|[A-Za-z]+Err(or)?\.message|\be\.message)/.test(line)) {
        offenders.push(`${dir.name}/index.ts:${i + 1}: ${line.trim()}`);
      }
    });
  }
  assertEquals(offenders, []);
});
