// The web build's e2e flow (#102): serves the test web export, opens it in headless Chrome and
// waits for the line game/test_mode.gd prints to the console when the device flow ends. Any error
// on the console or the page until then fails it too (after it, the game is quitting). A run that
// can't finish says why and ends at once (#252): the page crashing, the browser going away, WebGL
// losing its context, or the page no longer answering at all. It films the run into <export>-video/web-e2e.webm (owner,
// #115). Run by CI; the browser comes from the CHROME variable, and Playwright's ffmpeg, which the
// video needs, from PLAYWRIGHT_BROWSERS_PATH.
// Usage: CHROME=<chrome-headless-shell> bun tests/web/web_e2e.ts [build/web-test]
import { resolve, sep } from "node:path";
import { chromium } from "playwright-core";

const root = resolve(process.argv[2] ?? "build/web-test");
const chrome = process.env.CHROME;
const RESULT = /^KHOVAX_E2E: (PASS|FAIL .*)$/;
const TIMEOUT_MS = 180_000;
// How often the page is asked whether it still answers, and how long it may take.
const HEARTBEAT_MS = 10_000;
const ANSWER_MS = 5_000;
// Small enough that the software-rendered WebGL and the video encoder keep up on a busy runner
// (#193).
const SIZE = { width: 960, height: 540 };
const video = `${root}-video`;

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
let ended = false;
try {
  const context = await browser.newContext({
    viewport: SIZE,
    recordVideo: { dir: video, size: SIZE },
  });
  const page = await context.newPage();
  const started = Date.now();
  const seconds = () => Math.round((Date.now() - started) / 1000);
  // Ends the run early, failed, saying why.
  let stop: (why: string) => void = () => {};
  const stopped = new Promise<string>((done) => {
    stop = (why: string) => {
      if (ended) return;
      ended = true;
      errors.push(`${why} after ${seconds()} s`);
      done("");
    };
  });
  page.on("crash", () => stop("the page crashed"));
  browser.on("disconnected", () => stop("the browser went away"));
  // The canvas's context-lost events don't bubble, but they pass the document on their way down.
  await page.addInitScript(() => {
    document.addEventListener("webglcontextlost", () => console.error("WebGL lost its context"), true);
  });
  const reported = new Promise<string>((done) => {
    page.on("console", (message) => {
      const line = message.text();
      console.log(`[${message.type()}] ${line}`);
      if (message.type() === "error" && !ended) errors.push(line);
      if (line === "WebGL lost its context") stop("WebGL lost its context");
      const match = RESULT.exec(line);
      if (match) {
        ended = true;
        done(match[0]);
      }
    });
  });
  page.on("pageerror", (error) => ended || errors.push(error.message));
  page.on("requestfailed", (request) => ended || errors.push(`failed to load ${request.url()}`));
  await page.goto(server.url.href);
  const timeout = new Promise<string>((done) =>
    setTimeout(() => done(""), TIMEOUT_MS),
  );
  const heartbeat = setInterval(async () => {
    const answer = page.evaluate(() => performance.now()).then(() => true, () => true);
    const silence = new Promise<boolean>((done) => setTimeout(() => done(false), ANSWER_MS));
    if (!ended && !(await Promise.race([answer, silence]))) {
      stop(`the page stopped answering (no reply within ${ANSWER_MS / 1000} s)`);
    }
  }, HEARTBEAT_MS);
  result = await Promise.race([reported, stopped, timeout]);
  clearInterval(heartbeat);
  // Closing the browser below is no failure of the run.
  ended = true;
  // The video is written when its page closes.
  await context.close();
  await page.video()?.saveAs(`${video}/web-e2e.webm`);
  await page.video()?.delete();
} finally {
  await browser.close();
  server.stop(true);
}

const early = errors.length > 0 ? "the run ended early" : "";
console.log(result || early || `no result within ${TIMEOUT_MS / 1000} s: the game never reported`);
for (const error of errors) console.log(`console error: ${error}`);
process.exit(result === "KHOVAX_E2E: PASS" && errors.length === 0 ? 0 : 1);
