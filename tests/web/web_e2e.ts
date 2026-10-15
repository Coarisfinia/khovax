// The web build's e2e flow (#102): serves the test web export, opens it in headless Chrome and
// waits for the line game/test_mode.gd prints to the console when the device flow ends. Any error
// on the console or the page fails it too. Run by CI; the browser comes from the CHROME variable.
// Usage: CHROME=<chrome-headless-shell> bun tests/web/web_e2e.ts [build/web-test]
import { resolve, sep } from "node:path";
import { chromium } from "playwright-core";

const root = resolve(process.argv[2] ?? "build/web-test");
const chrome = process.env.CHROME;
const RESULT = /^KHOVAX_E2E: (PASS|FAIL .*)$/;
const TIMEOUT_MS = 180_000;

if (!chrome) {
  console.error("CHROME isn't set: point it at chrome-headless-shell");
  process.exit(2);
}

// The export as static files. Bun picks each file's type from its extension (.wasm included).
const server = Bun.serve({
  port: 0,
  async fetch(request) {
    const path = decodeURIComponent(new URL(request.url).pathname);
    const file = resolve(root, "." + (path === "/" ? "/index.html" : path));
    if (!file.startsWith(root + sep) || !(await Bun.file(file).exists())) {
      return new Response("not found", { status: 404 });
    }
    return new Response(Bun.file(file));
  },
});

// The runner has no GPU: WebGL 2 comes from Chrome's software renderer, which it only offers
// when asked to.
const browser = await chromium.launch({
  executablePath: chrome,
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
});
const errors: string[] = [];
let result = "";
try {
  const page = await browser.newPage();
  const ended = new Promise<string>((done) => {
    page.on("console", (message) => {
      const line = message.text();
      console.log(`[${message.type()}] ${line}`);
      if (message.type() === "error") errors.push(line);
      const match = RESULT.exec(line);
      if (match) done(match[0]);
    });
  });
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("requestfailed", (request) => errors.push(`failed to load ${request.url()}`));
  await page.goto(server.url.href);
  const timeout = new Promise<string>((done) =>
    setTimeout(() => done(""), TIMEOUT_MS),
  );
  result = await Promise.race([ended, timeout]);
} finally {
  await browser.close();
  server.stop(true);
}

console.log(result || `no result within ${TIMEOUT_MS / 1000} s: the game never reported`);
for (const error of errors) console.log(`console error: ${error}`);
process.exit(result === "KHOVAX_E2E: PASS" && errors.length === 0 ? 0 : 1);
