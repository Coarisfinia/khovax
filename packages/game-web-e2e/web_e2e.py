"""The web build's e2e flow (#102): serves the test web export, opens it in headless Chrome and
waits for the line game/test_mode.gd prints to the console when the device flow ends. Any error on
the console or the page until then fails it too (after it, the game is quitting). A run that can't
finish says why and ends at once (#252): the page crashing, the browser going away, WebGL losing
its context, or the page no longer answering at all. It films the run into
<export>-video/web-e2e.webm (owner, #115). Run by CI; the browser comes from the CHROME variable,
and Playwright's ffmpeg, which the video needs, from PLAYWRIGHT_BROWSERS_PATH (Playwright's own
browsers are never installed). The flow must end in the state hash the headless run of the same
commit ended in (#876), from the EXPECTED_HASH variable. At its end the flow saves the error log
with a controller's press alone (#1598): the run checks that the browser let it through as a
download named errors.log holding the web build's log, while the page never had user activation,
as for a player who only ever pressed a controller.

    CHROME=<chrome-headless-shell> EXPECTED_HASH=<hash> \
        uv run --locked --package khovax-game-web-e2e packages/game-web-e2e/web_e2e.py [build/web-test]
"""

import asyncio
import functools
import os
import re
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.async_api import CDPSession, Download, async_playwright

RESULT = re.compile(r"^KHOVAX_E2E: (PASS -?[0-9]+|FAIL .*)$")
TIMEOUT_S = 180
# How often the page is asked whether it still answers, how long it may take, and how many answers
# in a row it may miss before it counts as frozen: the game loads in one blocking step, which a
# slow software renderer can stretch, so one missed answer isn't enough.
HEARTBEAT_S = 10
ANSWER_S = 10
MISSES = 3
# How long the error log's download may take to arrive after the flow reported.
SAVE_S = 20
# The file the Credits tab's error log button saves (ErrorLogButton.FILE_NAME), and how its second
# line starts: the platform, as the log's header names it (ErrorLog.header).
SAVED_NAME = "errors.log"
SAVED_PLATFORM = "Web "
# Small enough that the software-rendered WebGL and the video encoder keep up on a busy runner
# (#193).
SIZE = {"width": 960, "height": 540}

# Without a GPU, WebGL 2 comes from a software renderer, chosen by CHROME_GL (#252): Mesa's
# llvmpipe through EGL, which CI uses, since on Chrome's own SwiftShader the page sometimes froze
# for good; or SwiftShader (which Chrome only offers when asked to), where Mesa isn't installed.
# Chrome quietly falls back to its own when it can't use the one asked for, so each names what its
# renderer string must contain.
GL: dict[str, dict] = {
    "swiftshader": {
        "args": ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
        "env": {},
        "expect": "SwiftShader",
    },
    "mesa": {
        "args": ["--use-gl=angle", "--use-angle=gl-egl", "--ignore-gpu-blocklist"],
        "env": {"LIBGL_ALWAYS_SOFTWARE": "1", "MESA_LOADER_DRIVER_OVERRIDE": "llvmpipe"},
        "expect": "llvmpipe",
    },
}

# The captions the loading screen shows (#270, the web presets' head_include), then none. The
# engine reports progress once a frame, so on a fast load it can start before the bar ever fills:
# the page then has nothing to switch on and goes straight from downloading to gone (#413).
CAPTIONS = "Downloading…,Starting the game…,gone"
CAPTIONS_UNFILLED = "Downloading…,gone"

# Which WebGL 2 renderer the page really got, since the flags only ask for one.
RENDERER_JS = """() => {
  const webgl = document.createElement("canvas").getContext("webgl2");
  if (!webgl) return "none";
  const info = webgl.getExtension("WEBGL_debug_renderer_info");
  return String(webgl.getParameter(info ? info.UNMASKED_RENDERER_WEBGL : webgl.RENDERER));
}"""

# The canvas's context-lost events don't bubble, but they pass the document on their way down.
# The loading screen's snake (#264, the web presets' head_include) says when it's on and gone, and
# its caption (#270) what it says. A mutation observer sees each caption the moment it's set, even
# when the engine's start blocks the page right after. Every record counts, so two captions set in
# one task are both seen. The bar is checked in the same microtask checkpoint as the page's own
# observer, so a full bar it saw is seen here.
WATCH_JS = """
document.addEventListener("webglcontextlost", () => console.error("WebGL lost its context"), true);
let shown = false;
(function watch() {
  const on = document.getElementById("khovax-snake") !== null;
  if (on && !shown) console.log("KHOVAX_SNAKE: shown");
  if (shown && !on) return console.log("KHOVAX_SNAKE: gone");
  shown = on;
  requestAnimationFrame(watch);
})();
const caption = (node) => node instanceof Element && node.id === "khovax-start";
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
}).observe(document, { childList: true, subtree: true, attributeFilter: ["value", "max"] });
"""


class Files(SimpleHTTPRequestHandler):
    """The export as static files, typed by their extension (.wasm included); paths can't leave
    the export's folder."""

    def log_message(self, format: str, *args: object) -> None:
        pass


def serve(root: Path) -> ThreadingHTTPServer:
    server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Files, directory=str(root)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class Run:
    """What the run saw: its result, its errors and what the loading screen reported."""

    def __init__(self) -> None:
        self.errors: list[str] = []
        self.result = ""
        # Whether the run is over: errors after it don't count (the game is quitting).
        self.ended = False
        # Why the run stopped early, or "" when it didn't.
        self.stop_reason = ""
        # What the loading screen's snake reported, in order.
        self.snake: list[str] = []
        # What the loading screen's caption said, in order.
        self.captions: list[str] = []
        # Whether the loading screen's bar was ever full.
        self.bar_full = False
        loop = asyncio.get_running_loop()
        self.reported: asyncio.Future[str] = loop.create_future()
        # The first download the page started, the error log's.
        self.download: asyncio.Future[Download] = loop.create_future()
        self.stopped: asyncio.Future[str] = loop.create_future()
        self.started = time.monotonic()

    def stop(self, why: str) -> None:
        """Ends the run early, failed, saying why."""
        if self.ended:
            return
        self.ended = True
        self.stop_reason = f"{why} after {round(time.monotonic() - self.started)} s"
        self.errors.append(self.stop_reason)
        self.stopped.set_result("")

    def console(self, kind: str, line: str) -> None:
        print(f"[{kind}] {line}")
        if kind == "error" and not self.ended:
            self.errors.append(line)
        if line.startswith("KHOVAX_SNAKE: "):
            self.snake.append(line.removeprefix("KHOVAX_SNAKE: "))
        if line.startswith("KHOVAX_CAPTION: "):
            self.captions.append(line.removeprefix("KHOVAX_CAPTION: "))
        if line == "KHOVAX_BAR: full":
            self.bar_full = True
        if line == "WebGL lost its context":
            self.stop("WebGL lost its context")
        if RESULT.match(line) and not self.reported.done():
            self.ended = True
            self.reported.set_result(line)

    def downloaded(self, download: Download) -> None:
        if not self.download.done():
            self.download.set_result(download)

    def error(self, message: str) -> None:
        if not self.ended:
            self.errors.append(message)


async def quietly(cdp: CDPSession, expression: str) -> object:
    """Evaluates `expression` on the page without giving it user activation: Playwright's own
    evaluate passes the DevTools protocol's userGesture, which would count as a click for the
    browser and spoil the controller-only save (#1598)."""
    answer = await cdp.send("Runtime.evaluate", {"expression": expression, "returnByValue": True})
    return answer["result"].get("value")


async def heartbeat(cdp: CDPSession, run: Run) -> None:
    """Asks the page every HEARTBEAT_S whether it still answers, and stops the run once it missed
    MISSES answers in a row."""
    missed = 0
    beat = time.monotonic()
    while True:
        beat += HEARTBEAT_S
        await asyncio.sleep(max(0.0, beat - time.monotonic()))
        try:
            await asyncio.wait_for(quietly(cdp, "true"), ANSWER_S)
            missed = 0
        except Exception:
            missed += 1
        if missed >= MISSES:
            run.stop(f"the page stopped answering ({MISSES} heartbeats in a row)")


async def check_saved_log(cdp: CDPSession, run: Run) -> None:
    """Checks that the flow's controller press saved the error log (#1598): a download named
    SAVED_NAME holding the web build's log arrived, and the page never had user activation."""
    await first(run.download, run.stopped, timeout=SAVE_S)
    if not run.download.done():
        run.errors.append(f"the error log saved by a controller never arrived within {SAVE_S} s")
        return
    download = run.download.result()
    if await quietly(cdp, "navigator.userActivation.hasBeenActive"):
        run.errors.append("the page had user activation, so the controller's save proves nothing")
    if download.suggested_filename != SAVED_NAME:
        name = download.suggested_filename
        run.errors.append(f"the error log was saved as {name}, not {SAVED_NAME}")
        return
    lines = Path(await download.path()).read_text(encoding="utf-8").splitlines()
    if len(lines) < 2 or not lines[1].startswith(SAVED_PLATFORM):
        run.errors.append(f"the saved error log doesn't start with the web's header: {lines[:2]}")


async def first(*waits: asyncio.Future, timeout: float | None = None) -> None:
    """Waits until the first of them is done, or the timeout passes."""
    await asyncio.wait(waits, timeout=timeout, return_when=asyncio.FIRST_COMPLETED)


async def play(root: Path, chrome: str, gl: str, run: Run) -> None:
    server = serve(root)
    try:
        await drive(root, chrome, gl, run, f"http://127.0.0.1:{server.server_port}/")
    finally:
        server.shutdown()


async def drive(root: Path, chrome: str, gl: str, run: Run, url: str) -> None:
    video = Path(f"{root}-video")
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(
            executable_path=chrome,
            args=GL[gl]["args"],
            env={**os.environ, **GL[gl]["env"]},
        )
        try:
            context = await browser.new_context(
                viewport=SIZE, record_video_dir=str(video), record_video_size=SIZE
            )
            page = await context.new_page()
            cdp = await context.new_cdp_session(page)
            renderer = str(await quietly(cdp, f"({RENDERER_JS})()"))
            print(f"CHROME_GL {gl}: WebGL 2 renderer {renderer}")
            if GL[gl]["expect"] not in renderer:
                raise RuntimeError(f"CHROME_GL {gl} asked for {GL[gl]['expect']}, but got {renderer}")
            run.started = time.monotonic()
            page.on("crash", lambda _: run.stop("the page crashed"))
            page.on("close", lambda _: run.stop("the page closed"))
            browser.on("disconnected", lambda _: run.stop("the browser went away"))
            await page.add_init_script(WATCH_JS)
            page.on("console", lambda message: run.console(message.type, message.text))
            page.on("download", run.downloaded)
            page.on("pageerror", lambda error: run.error(error.message))
            page.on("requestfailed", lambda request: run.error(f"failed to load {request.url}"))

            # A page that crashes while it loads ends the run there, not when navigation gives up.
            async def load() -> None:
                try:
                    await page.goto(url)
                except Exception:
                    pass

            loading = asyncio.ensure_future(load())
            await first(loading, run.stopped)
            beating = asyncio.ensure_future(heartbeat(cdp, run))
            await first(run.reported, run.stopped, timeout=TIMEOUT_S)
            reported = run.reported.done() and not run.stop_reason
            if reported and run.reported.result().startswith("KHOVAX_E2E: PASS "):
                await check_saved_log(cdp, run)
            beating.cancel()
            loading.cancel()
            if run.reported.done() and not run.stop_reason:
                run.result = run.reported.result()
            # The snake was on the loading screen while the game loaded, and went with it.
            if run.result and ",".join(run.snake) != "shown,gone":
                got = ",".join(run.snake) or "nothing"
                run.errors.append(f"the loading screen's snake reported {got}, not shown,gone")
            # The loading screen said what it was doing, step by step, and its caption went with
            # it: once its bar was full, it said the game was starting.
            expected = CAPTIONS if run.bar_full else CAPTIONS_UNFILLED
            if run.result and ",".join(run.captions) != expected:
                got = ",".join(run.captions) or "none"
                run.errors.append(f"the loading screen's captions were {got}, not {expected}")
            # Closing the browser below is no failure of the run.
            run.ended = True
            # The video is written when its page closes. Best effort: after a crash or a lost
            # browser this can fail, and that mustn't hide why the run stopped.
            try:
                await context.close()
                if page.video:
                    await page.video.save_as(video / "web-e2e.webm")
                    await page.video.delete()
            except Exception as error:
                print(f"the video couldn't be saved: {error}")
        finally:
            try:
                await browser.close()
            except Exception:
                pass


async def main() -> int:
    # Each line reaches CI's log at once, also when the step's timeout kills the run.
    sys.stdout.reconfigure(line_buffering=True)
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web-test").resolve()
    chrome = os.environ.get("CHROME")
    expected_hash = os.environ.get("EXPECTED_HASH")
    gl = os.environ.get("CHROME_GL", "swiftshader")
    if not chrome:
        print("CHROME isn't set: point it at chrome-headless-shell", file=sys.stderr)
        return 2
    if not expected_hash:
        print("EXPECTED_HASH isn't set: the headless run's final state hash", file=sys.stderr)
        return 2
    if gl not in GL:
        print(f"CHROME_GL is {gl}, not one of {', '.join(GL)}", file=sys.stderr)
        return 2
    run = Run()
    await play(root, chrome, gl, run)

    timed_out = f"no result within {TIMEOUT_S} s: the game never reported"
    early = f"the run stopped early: {run.stop_reason}" if run.stop_reason else timed_out
    print(run.result or early)
    for error in run.errors:
        print(f"console error: {error}")
    passed = f"KHOVAX_E2E: PASS {expected_hash}"
    if run.result.startswith("KHOVAX_E2E: PASS ") and run.result != passed:
        print(f"the headless run ended in state {expected_hash}")
    return 0 if run.result == passed and not run.errors else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
