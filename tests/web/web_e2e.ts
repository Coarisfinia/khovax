// The web build's e2e flow (#102): serves the test web export, opens it in headless Chrome and
// waits for the line game/test_mode.gd prints to the console when the device flow ends. Any error
// on the console or the page until then fails it too (after it, the game is quitting). A run that
// can't finish says why and ends at once (#252): the page crashing, the browser going away, WebGL
// losing its context, or the page no longer answering at all. It films the run into <export>-video/web-e2e.webm (owner,
// #115). Run by CI; the browser comes from the CHROME variable, and Playwright's ffmpeg, which the
// video needs, from PLAYWRIGHT_BROWSERS_PATH. The flow must end in the state hash the headless run of
// the same commit ended in (#876), from the EXPECTED_HASH variable.
// Usage: CHROME=<chrome-headless-shell> EXPECTED_HASH=<hash> bun tests/web/web_e2e.ts [build/web-test]
import { resolve, sep } from "node:path";
import { chromium } from "playwright-core";

const root = resolve(process.argv[2] ?? "build/web-test");
const chrome = process.env.CHROME;
const expectedHash = process.env.EXPECTED_HASH;
const RESULT = /^KHOVAX_E2E: (PASS -?[0-9]+|FAIL .*)$/;
const TIMEOUT_MS = 180_000;
// How often the page is asked whether it still answers, how long it may take, and how many
// answers in a row it may miss before it counts as frozen: the game loads in one blocking step,
// which a slow software renderer can stretch, so one missed answer isn't enough.
const HEARTBEAT_MS = 10_000;
const ANSWER_MS = 10_000;
const MISSES = 3;
// Small enough that the software-rendered WebGL and the video encoder keep up on a busy runner
// (#193).
const SIZE = { width: 960, height: 540 };
const video = `${root}-video`;

if (!chrome) {
  console.error("CHROME isn't set: point it at chrome-headless-shell");
  process.exit(2);
}
if (!expectedHash) {
  console.error("EXPECTED_HASH isn't set: the headless run's final state hash");
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

// Without a GPU, WebGL 2 comes from a software renderer, chosen by CHROME_GL (#252): Mesa's
// llvmpipe through EGL, which CI uses, since on Chrome's own SwiftShader the page sometimes froze
// for good; or SwiftShader (which Chrome only offers when asked to), where Mesa isn't installed.
// Chrome quietly falls back to its own when it can't use the one asked for, so each names what its
// renderer string must contain.
const GL: Record<string, { args: string[]; env: Record<string, string>; expect: string }> = {
  swiftshader: {
    args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
    env: {},
    expect: "SwiftShader",
  },
  mesa: {
    args: ["--use-gl=angle", "--use-angle=gl-egl", "--ignore-gpu-blocklist"],
    env: { LIBGL_ALWAYS_SOFTWARE: "1", MESA_LOADER_DRIVER_OVERRIDE: "llvmpipe" },
    expect: "llvmpipe",
  },
};
const gl = process.env.CHROME_GL ?? "swiftshader";
if (!GL[gl]) {
  console.error(`CHROME_GL is ${gl}, not one of ${Object.keys(GL).join(", ")}`);
  process.exit(2);
}
const browser = await chromium.launch({
  executablePath: chrome,
  args: GL[gl].args,
  env: { ...process.env, ...GL[gl].env },
});
const errors: string[] = [];
let result = "";
let ended = false;
// Why the run stopped early, or "" when it didn't.
let stopReason = "";
// What the loading screen's snake reported, in order.
const snake: string[] = [];
// What the loading screen's caption said, in order.
const captions: string[] = [];
// Whether the loading screen's bar was ever full.
let barFull = false;
// The captions the loading screen shows (#270, the web presets' head_include), then none. The
// engine reports progress once a frame, so on a fast load it can start before the bar ever fills:
// the page then has nothing to switch on and goes straight from downloading to gone (#413).
const CAPTIONS = "Downloading…,Starting the game…,gone";
const CAPTIONS_UNFILLED = "Downloading…,gone";
try {
  const context = await browser.newContext({
    viewport: SIZE,
    recordVideo: { dir: video, size: SIZE },
  });
  const page = await context.newPage();
  // Which renderer the run really got, since the flags only ask for one.
  const renderer = await page.evaluate(() => {
    const webgl = document.createElement("canvas").getContext("webgl2");
    if (!webgl) return "none";
    const info = webgl.getExtension("WEBGL_debug_renderer_info");
    return String(webgl.getParameter(info ? info.UNMASKED_RENDERER_WEBGL : webgl.RENDERER));
  });
  console.log(`CHROME_GL ${gl}: WebGL 2 renderer ${renderer}`);
  if (!renderer.includes(GL[gl].expect)) {
    throw new Error(`CHROME_GL ${gl} asked for ${GL[gl].expect}, but got ${renderer}`);
  }
  const started = Date.now();
  const seconds = () => Math.round((Date.now() - started) / 1000);
  // Ends the run early, failed, saying why.
  let stop: (why: string) => void = () => {};
  const stopped = new Promise<string>((done) => {
    stop = (why: string) => {
      if (ended) return;
      ended = true;
      stopReason = `${why} after ${seconds()} s`;
      errors.push(stopReason);
      done("");
    };
  });
  page.on("crash", () => stop("the page crashed"));
  page.on("close", () => stop("the page closed"));
  browser.on("disconnected", () => stop("the browser went away"));
  // The canvas's context-lost events don't bubble, but they pass the document on their way down.
  // The loading screen's snake (#264, the web presets' head_include) says when it's on and gone,
  // and its caption (#270) what it says. A mutation observer sees each caption the moment it's
  // set, even when the engine's start blocks the page right after.
  await page.addInitScript(() => {
    document.addEventListener("webglcontextlost", () => console.error("WebGL lost its context"), true);
    let shown = false;
    (function watch() {
      const on = document.getElementById("khovax-snake") !== null;
      if (on && !shown) console.log("KHOVAX_SNAKE: shown");
      if (shown && !on) return console.log("KHOVAX_SNAKE: gone");
      shown = on;
      requestAnimationFrame(watch);
    })();
    // Every record counts, so two captions set in one task are both seen. The bar is checked in
    // the same microtask checkpoint as the page's own observer, so a full bar it saw is seen here.
    const caption = (node: Node | null) => node instanceof Element && node.id === "khovax-start";
    let full = false;
    new MutationObserver((records) => {
      for (const record of records) {
        const bar = record.target;
        const loading = bar instanceof HTMLProgressElement && bar.id === "status-progress";
        if (!full && loading && bar.max > 0 && bar.value >= bar.max) {
          full = true;
          console.log("KHOVAX_BAR: full");
        }
        for (const node of record.addedNodes) {
          if (caption(node) || caption(record.target)) {
            console.log(`KHOVAX_CAPTION: ${node.textContent}`);
          }
        }
        for (const node of record.removedNodes) {
          if (caption(node) || (node instanceof Element && node.querySelector("#khovax-start"))) {
            console.log("KHOVAX_CAPTION: gone");
          }
        }
      }
    }).observe(document, {
      childList: true,
      subtree: true,
      attributeFilter: ["value", "max"],
    });
  });
  const reported = new Promise<string>((done) => {
    page.on("console", (message) => {
      const line = message.text();
      console.log(`[${message.type()}] ${line}`);
      if (message.type() === "error" && !ended) errors.push(line);
      if (line.startsWith("KHOVAX_SNAKE: ")) snake.push(line.slice(14));
      if (line.startsWith("KHOVAX_CAPTION: ")) captions.push(line.slice(16));
      if (line === "KHOVAX_BAR: full") barFull = true;
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
  // A page that crashes while it loads ends the run there, not when navigation gives up.
  await Promise.race([page.goto(server.url.href).catch(() => {}), stopped]);
  const timeout = new Promise<string>((done) =>
    setTimeout(() => done(""), TIMEOUT_MS),
  );
  let missed = 0;
  const heartbeat = setInterval(async () => {
    const answer = page.evaluate(() => true).catch(() => false);
    const silence = new Promise<boolean>((done) => setTimeout(() => done(false), ANSWER_MS));
    missed = (await Promise.race([answer, silence])) ? 0 : missed + 1;
    if (missed >= MISSES) {
      stop(`the page stopped answering (${MISSES} heartbeats in a row)`);
    }
  }, HEARTBEAT_MS);
  result = await Promise.race([reported, stopped, timeout]);
  clearInterval(heartbeat);
  // The snake was on the loading screen while the game loaded, and went with it.
  if (result && snake.join() !== "shown,gone") {
    errors.push(`the loading screen's snake reported ${snake.join() || "nothing"}, not shown,gone`);
  }
  // The loading screen said what it was doing, step by step, and its caption went with it: once
  // its bar was full, it said the game was starting.
  const expected = barFull ? CAPTIONS : CAPTIONS_UNFILLED;
  if (result && captions.join() !== expected) {
    errors.push(`the loading screen's captions were ${captions.join() || "none"}, not ${expected}`);
  }
  // Closing the browser below is no failure of the run.
  ended = true;
  // The video is written when its page closes. Best effort: after a crash or a lost browser this
  // can fail, and that mustn't hide why the run stopped.
  try {
    await context.close();
    await page.video()?.saveAs(`${video}/web-e2e.webm`);
    await page.video()?.delete();
  } catch (error) {
    console.log(`the video couldn't be saved: ${error}`);
  }
} finally {
  await browser.close().catch(() => {});
  server.stop(true);
}

const timedOut = `no result within ${TIMEOUT_MS / 1000} s: the game never reported`;
console.log(result || (stopReason ? `the run stopped early: ${stopReason}` : timedOut));
for (const error of errors) console.log(`console error: ${error}`);
const passed = `KHOVAX_E2E: PASS ${expectedHash}`;
if (result.startsWith("KHOVAX_E2E: PASS ") && result !== passed) {
  console.log(`the headless run ended in state ${expectedHash}`);
}
process.exit(result === passed && errors.length === 0 ? 0 : 1);
