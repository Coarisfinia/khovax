"""Tests render_media.py's run when a job fails (#1694), with the renders, ffmpeg, the GIFs and the
publishing stood in for: the pictures the other jobs made are still published, the media block
leaves the missing ones out and lists them with their job's log, and the run exits 1.

    uv run --locked --package khovax-game-models packages/game-models/test_render_media.py

It prints `RENDER MEDIA TEST: PASS` or `FAIL` (and exits 1 on a fail)."""

import contextlib
import io
import sys
import tempfile
from pathlib import Path
from unittest import mock

import render_media

MODEL = next(iter(sorted(render_media.GAME.glob("assets/*/*.glb"))))
CLIPS = ["Idle", "Walk"]


def fake_run(failing: dict[str, int | None]):
    """A stand-in for render_media.run: each job writes the pictures it would make, unless it is
    in `failing`, which gives its exit code (None: it timed out)."""
    def run(_command: list[str], log_path: Path, timeout: float) -> int | None:
        log_path.write_text("log\n")
        name = log_path.stem
        if name in failing:
            return failing[name]
        if name == "import":
            return 0
        out = log_path.parent.parent / name  # every job renders into <out>/<its name>
        out.mkdir(parents=True, exist_ok=True)
        if name == "sheet":
            (out / "sheet.png").write_bytes(b"png")
        elif name == "desktop":
            for picture in ("game", "portrait", "face", *render_media.SIDES):
                (out / f"{picture}.png").write_bytes(b"png")
        elif name in ("phone", "points"):
            (out / ("game.png" if name == "phone" else "portrait.png")).write_bytes(b"png")
        elif name.startswith("clips-"):
            for clip in CLIPS:
                for frame in range(4):
                    (out / f"{clip}_{frame:03d}.png").write_bytes(b"png")
        return 0
    return run


class Output(io.StringIO):
    """The run's output, which render_media line-buffers like a terminal's."""

    def reconfigure(self, **_options: object) -> None:
        pass


def fake_ffmpeg(*_inputs: Path, filters: str, out: Path) -> bool:
    out.write_bytes(b"png")
    return True


def fake_gif(folder: Path, clip: str, out: Path) -> Path | None:
    if not any(folder.glob(f"{clip}_*.png")):
        return None
    out.write_bytes(b"gif")
    return out


def render(*flags: str, failing: dict[str, int | None], ffmpeg=None) -> tuple[int, list[str], str]:
    """Runs render_media with the stand-ins: its exit code, the published names and its output."""
    published: list[str] = []

    def publish(paths: list[Path]) -> bool:
        published.extend(path.name for path in paths)
        return True

    output = Output()
    with tempfile.TemporaryDirectory() as folder, \
            mock.patch.object(sys, "argv", ["render_media.py", str(MODEL), "--pr", "1", "--out", f"{folder}/out", *flags]), \
            mock.patch.object(render_media, "run", fake_run(failing)), \
            mock.patch.object(render_media, "ffmpeg", ffmpeg or fake_ffmpeg), \
            mock.patch.object(render_media.gif, "make", fake_gif), \
            mock.patch.object(render_media, "clips_of", lambda _model: list(CLIPS)), \
            mock.patch.object(render_media, "publish", publish), \
            mock.patch.object(render_media, "STAGGER", 0.0), \
            contextlib.redirect_stdout(output):
        code = render_media.main()
    return code, sorted(published), output.getvalue()


def check(failures: list[str], what: str, ok: bool) -> None:
    print(("ok: " if ok else "FAIL: ") + what)
    if not ok:
        failures.append(what)


def main() -> int:
    failures: list[str] = []

    code, published, output = render("--quick", failing={})
    check(failures, "every job succeeds: exit 0", code == 0)
    check(failures, "every job succeeds: every quick picture published",
          published == [f"pr-1-{key}.png" for key in sorted(("face", "game", "portrait", "sheet", "sides"))])
    check(failures, "every job succeeds: nothing listed as not rendered", "not rendered" not in output)

    code, published, output = render("--quick", failing={"sheet": 1})
    block = output.split("----- media block -----")[-1].split("----- not rendered -----")[0]
    check(failures, "the sheet fails: exit 1", code == 1)
    check(failures, "the sheet fails: the Godot pictures are still published",
          published == [f"pr-1-{key}.png" for key in sorted(("face", "game", "portrait", "sides"))])
    check(failures, "the sheet fails: the block leaves it out", "sheet" not in block and "pr-1-game.png" in block)
    check(failures, "the sheet fails: it is listed with its job's log",
          "- sheet: sheet failed (1): " in output and "sheet.log" in output)
    check(failures, "the sheet fails: the failed job is named", "failed: sheet" in output)

    code, published, output = render(failing={"clips-close": None, "phone": 2})
    block = output.split("----- media block -----")[-1].split("----- not rendered -----")[0]
    check(failures, "two jobs fail: exit 1", code == 1)
    check(failures, "two jobs fail: the rest is published",
          "pr-1-sheet.png" in published and "pr-1-points.png" in published and "pr-1-Walk.gif" in published
          and "pr-1-phone.png" not in published and not any("close-" in name for name in published))
    check(failures, "two jobs fail: the clip table marks the close GIFs as missing",
          "| **Walk** | ![](" in block and "| *not rendered* |" in block and "![phone]" not in block)
    check(failures, "two jobs fail: the timeout and the failure are listed with their logs",
          "- close-Idle: clips-close timed out" in output and "- phone: phone failed (2): " in output)

    def no_tiles(*inputs: Path, filters: str, out: Path) -> bool:
        return "hstack=inputs=4" not in filters and fake_ffmpeg(*inputs, filters=filters, out=out)

    code, published, output = render(failing={}, ffmpeg=no_tiles)
    check(failures, "a clip's tile fails: exit 1, the GIFs still published, the tile listed",
          code == 1 and "pr-1-Walk.gif" in published and "- tiles/game-Walk.png: " in output)

    code, published, output = render("--quick", failing={"sheet": 1, "desktop": 1})
    check(failures, "every job fails: exit 1, nothing published", code == 1 and not published)

    print(f"RENDER MEDIA TEST: {'FAIL' if failures else 'PASS'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
