"""Tests web_e2e.py's page checks without a browser (#1819), with the page and the download stood
in for: a script that throws on the page fails the check instead of passing it, the page's user
activation must be exactly false, and an error log download that fails or never finishes is a
failure of the run, not a traceback or a wait until CI's timeout.

    uv run --locked --package khovax-game-web-e2e packages/game-web-e2e/test_web_e2e.py

It prints `WEB E2E TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import asyncio
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

import web_e2e

# How long a check may take here before it counts as stuck: well above the shortened SAVE_S.
STUCK_S = 5.0
THROWN = {
    "result": {"type": "object", "subtype": "error"},
    "exceptionDetails": {"text": "Uncaught", "exception": {"description": "TypeError: boom"}},
}


class Page:
    """A stand-in for the page's DevTools session: answers each expression from `answers`."""

    def __init__(self, answers: dict[str, dict]) -> None:
        self.answers = answers

    async def send(self, _method: str, params: dict) -> dict:
        return self.answers[params["expression"]]


class Download:
    """A stand-in for the error log's download: `path` returns `saved`, raises it, or never
    finishes when it is None."""

    def __init__(self, saved: Path | Exception | None) -> None:
        self.suggested_filename = web_e2e.SAVED_NAME
        self.saved = saved

    async def path(self) -> Path:
        if self.saved is None:
            await asyncio.Event().wait()
        if isinstance(self.saved, Exception):
            raise self.saved
        return self.saved


def activation(answer: dict) -> Page:
    return Page({"navigator.userActivation.hasBeenActive": answer})


def value(answer: object) -> dict:
    return {"result": {"type": "boolean", "value": answer}}


async def checked(page: Page, download: Download | None) -> list[str]:
    """The errors check_saved_log reports for the page and the download (None: none arrived); a
    check that raises or gets stuck reports that as its error."""
    run = web_e2e.Run()
    if download:
        run.downloaded(download)
    try:
        await asyncio.wait_for(web_e2e.check_saved_log(page, run), STUCK_S)
    except TimeoutError:
        return [f"STUCK for {STUCK_S} s"]
    except Exception as error:
        return [f"RAISED {error!r}"]
    return run.errors


async def cases(log: Path) -> list[str]:
    """Each failed case, with what it got."""
    failed: list[str] = []

    def expect(name: str, ok: bool, got: object) -> None:
        print(f"{'ok' if ok else 'FAIL'}: {name}: {got}")
        if not ok:
            failed.append(name)

    try:
        got: object = await web_e2e.quietly(Page({"x": THROWN}), "x")
        expect("quietly raises on a thrown script", False, f"returned {got!r}")
    except Exception as error:
        expect("quietly raises on a thrown script", "boom" in str(error), repr(error))
    got = await web_e2e.quietly(Page({"x": value(False)}), "x")
    expect("quietly returns the script's value", got is False, repr(got))

    errors = await checked(activation(value(False)), Download(log))
    expect("a clean save passes", errors == [], errors)
    for name, answer in [("throws", THROWN), ("is missing", {"result": {"type": "undefined"}})]:
        errors = await checked(activation(answer), Download(log))
        ok = len(errors) == 1 and "activation" in errors[0]
        expect(f"user activation that {name} fails the check", ok, errors)
    errors = await checked(activation(value(True)), Download(log))
    expect("user activation fails the check", len(errors) == 1, errors)

    errors = await checked(activation(value(True)), None)
    ok = len(errors) == 2 and any("activation" in error for error in errors)
    expect("a missing download still checks user activation", ok, errors)
    for name, saved in [("fails", OSError("download failed")), ("never finishes", None)]:
        errors = await checked(activation(value(False)), Download(saved))
        ok = len(errors) == 1 and not errors[0].startswith(("RAISED", "STUCK"))
        expect(f"a download that {name} is a failure of the run", ok, errors)
    return failed


def main() -> int:
    # The download's wait, shortened so a stuck one shows within STUCK_S.
    web_e2e.SAVE_S = 0.5
    with TemporaryDirectory() as folder:
        log = Path(folder) / web_e2e.SAVED_NAME
        log.write_text(f"khovax error log\n{web_e2e.SAVED_PLATFORM}build\n", encoding="utf-8")
        failed = asyncio.run(cases(log))
    print(f"WEB E2E TEST: {'FAIL ' + ', '.join(failed) if failed else 'PASS'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
