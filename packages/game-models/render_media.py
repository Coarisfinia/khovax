"""Renders a model's pictures for its pull request in one command (#1525), publishes them on the
assets branch and prints the description's media block, ready to paste.

    uv run --locked --package khovax-game-models packages/game-models/render_media.py \
        packages/game/assets/<name>/<name>.glb --pr <n> [--tag v2] [--quick] [--out <folder>] \
        [--jobs 3] [--timeout 900] [--no-publish]

It runs what a model pull request shows (the model skill's step 5), Blender and Godot side by side
(both on the CPU: Blender's sheets with Cycles, since EEVEE hangs under WSL, #1676), and Godot
only off the desktop, through offscreen.py:
- Blender, `render_views.py`: the sheet of every side at rest, and with every clip, each clip's
  middle pose as a sheet of its own (the pose sheets, for looking at, not published).
- Godot, `render_in_game.gd`: the game camera and six sides on the desktop screen, the close-ups
  (`portrait`, `face`), the phone's game camera, the attachment points (`points`, the portrait),
  and every clip's frames from the game camera and close up (the three-quarter view), each clip's
  GIF made with `gif.py`.
- A row of four frames per clip and view (`tiles/`), for looking at a clip where a GIF can't be
  seen; not published.

`--quick` renders only the fast-feedback pictures (the model skill, #1047): the Blender sheet and
the one Godot run on the desktop screen (the game camera, the sides and the close-ups). Run it
first, post its block, then run without it for the rest.

Every picture is published as `pr-<n>[-<tag>]-<what>`: the tag is the version (`v2` once the model
was rebuilt), so a later round never overwrites the pictures an earlier description links. The
Godot project is imported first, so the renders never show a stale import (#1164). It renders
into a fresh folder, never deleting anything; each job's log is in `<out>/logs/`. A job that runs
longer than `--timeout` seconds is stopped and fails, naming its log (#1676): a hung render
(Blender's sat at 0 % CPU for good) never keeps the run waiting forever. When jobs fail, the
pictures the others made are still published and the media block shows them without the missing
ones, which are listed after it, each with its job's log (#1694); the run then exits 1, so a
background run still shows it failed."""

import argparse
import concurrent.futures
import math
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path

import gif
from check_rebuild import read_glb
from game_shared import log
from lib import clip_set

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "packages" / "game"
RENDER_VIEWS = ROOT / ".claude" / "skills" / "model" / "scripts" / "render_views.py"
URL = "https://github.com/Coarisfinia/khovax/blob/assets/{}?raw=true"
# The sizes the recent model pull requests show (#1514): the desktop's screen, a phone's, and the
# clips' frames, which the GIFs keep at 640 pixels wide.
DESKTOP = "1280x720"
PHONE = "390x844"
CLIP_SIZE = "640x480"
SIDES = ("front", "back", "left", "right", "top", "three_quarter")
# The close view of the clips: the three-quarter view, which shows the face and the legs at once.
CLOSE = "three_quarter"
# Seconds between two Godot starts: xvfb-run picks a free display by looking, and two starting at
# once can pick the same one.
STAGGER = 3.0
# Seconds a job may take before it counts as hung (#1676). The slowest, a model's every clip in
# game, takes about three minutes.
TIMEOUT = 900
# Seconds a timed-out job gets to end after SIGTERM before it is killed.
GRACE = 10
# The jobs running now: their own process groups don't get the terminal's Ctrl-C, so an interrupted
# run stops them itself.
RUNNING: set[subprocess.Popen] = set()
RUNNING_LOCK = threading.Lock()
INTERRUPTED = threading.Event()


@dataclass
class Job:
    """One render: its name (its log's), the command and where it writes."""
    name: str
    command: list[str]
    out: Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Render, publish and describe a model's pictures.")
    parser.add_argument("model", type=Path, help="the model's .glb, inside packages/game")
    parser.add_argument("--pr", type=int, required=True, help="the pull request the pictures are for")
    parser.add_argument("--tag", default="", help="the version in the names, e.g. v2")
    parser.add_argument("--quick", action="store_true", help="only the fast-feedback pictures")
    parser.add_argument("--out", type=Path, help="an empty or new folder to render into (a new temporary one by default)")
    parser.add_argument("--jobs", type=int, default=3, help="Godot renders at once")
    parser.add_argument("--timeout", type=seconds, default=TIMEOUT,
                        help=f"seconds a job may take before it's stopped as hung (default {TIMEOUT})")
    parser.add_argument("--no-publish", action="store_true", help="render only, print local paths")
    args = parser.parse_args()
    # The jobs run in process groups of their own, which a SIGTERM or a closed terminal doesn't
    # reach: both end the run through the same clean-up as Ctrl-C, which stops them.
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda signum, _frame: sys.exit(128 + signum))
    # Progress shows as it happens, also when the output goes to a file (a background run's).
    sys.stdout.reconfigure(line_buffering=True)

    model = args.model.resolve()
    if not model.is_file() or GAME not in model.parents:
        log.error(f"{args.model}: no .glb inside {GAME.relative_to(ROOT)}, where Godot can load it")
        return 1
    prefix = f"pr-{args.pr}" + (f"-{args.tag}" if args.tag else "")
    # Always a fresh folder, so no frames from an earlier render join a clip's GIF, and nothing
    # already there is ever deleted: a new private one by default, or an empty or new `--out`.
    if args.out is None:
        out = Path(tempfile.mkdtemp(prefix=f"khovax-media-{prefix}-"))
    else:
        out = args.out.resolve()
        if out.exists() and (not out.is_dir() or any(out.iterdir())):
            log.error(f"{args.out} isn't an empty folder: name a new one, or leave --out out")
            return 1
    (out / "logs").mkdir(parents=True, exist_ok=True)
    clips = [] if args.quick else clips_of(model)
    resource = "res://" + model.relative_to(GAME).as_posix()

    log.info("importing the game project, so the renders show this build")
    imported = run(["godot", "--headless", "--path", str(GAME), "--import"], out / "logs" / "import.log",
                   args.timeout)
    if imported != 0:
        reason = f"timed out after {args.timeout:.0f} s" if imported is None else "failed"
        log.error(f"the import {reason}: {out / 'logs' / 'import.log'}")
        return 1

    blender = [blender_job("sheet", model, out / "sheet")]
    godot = [godot_job("desktop", resource, out / "desktop", f"size={DESKTOP}")]
    if not args.quick:
        if clips:
            blender.append(blender_job("poses", model, out / "poses", ",".join(clips), "mid"))
        godot += [
            godot_job("phone", resource, out / "phone", f"size={PHONE}"),
            godot_job("points", resource, out / "points", f"size={DESKTOP}", "points"),
        ]
        if clips:
            godot += [
                godot_job("clips-game", resource, out / "clips-game", f"size={CLIP_SIZE}",
                          "clip=" + ",".join(clips)),
                godot_job("clips-close", resource, out / "clips-close", f"size={CLIP_SIZE}",
                          "clip=" + ",".join(clips), f"from={CLOSE}"),
            ]
    failed = run_all(blender, godot, out / "logs", args.jobs, args.timeout)

    # What failed is left out, and everything else is still published (#1694).
    pictures, missing = collect(out, clips, args.quick, failed)
    if not pictures:
        log.error("nothing was rendered, so nothing is published")
        report(missing)
        return 1
    staged = stage(out / "publish", prefix, pictures)
    if not args.no_publish and not publish(list(staged.values())):
        log.error("publishing failed")
        return 1
    link = (lambda key: URL.format(staged[key].name)) if not args.no_publish else (lambda key: str(staged[key]))
    if clips:
        log.info(f"pose sheets: {out / 'poses'}; four-frame tiles: {out / 'tiles'}")
    print("\n----- media block -----\n")
    print(block(link, clips, args.quick, set(staged)))
    if failed or missing:
        report(missing)
        if failed:
            log.error(f"failed: {', '.join(failed)}")
        return 1
    return 0


def publish(paths: list[Path]) -> bool:
    """Publishes the pictures on the assets branch; True when that worked."""
    published = subprocess.run(
        ["uv", "run", "--locked", "--package", "khovax-game-visuals",
         str(ROOT / "packages" / "game-visuals" / "publish.py"), *map(str, paths)],
        cwd=ROOT, check=False,
    )
    return published.returncode == 0


def report(missing: dict[str, str]) -> None:
    """Lists each picture that wasn't made, with why (its job's log)."""
    if missing:
        print("\n----- not rendered -----\n")
        for key, why in missing.items():
            print(f"- {key}: {why}")


def seconds(text: str) -> float:
    """A timeout: a finite number of seconds above zero."""
    try:
        value = float(text)
    except ValueError:
        value = math.nan
    if not math.isfinite(value) or value <= 0:
        raise argparse.ArgumentTypeError(f"{text!r} isn't a number of seconds above zero")
    return value


def clips_of(model: Path) -> list[str]:
    """The model's clips: the creature set's in its order, then any others by name."""
    gltf, _binary = read_glb(model)
    names = [animation.get("name", "") for animation in gltf.get("animations", [])]
    ordered = [clip for clip in clip_set.CREATURE if clip in names]
    return ordered + sorted(set(names) - set(ordered) - {""})


def blender_job(name: str, model: Path, out: Path, *extra: str) -> Job:
    command = ["uv", "run", "--locked", str(ROOT / "packages" / "game-models" / "blender.py"),
               "--background", "--factory-startup", "--python", str(RENDER_VIEWS), "--",
               str(model), str(out), *extra]
    return Job(name, command, out)


def godot_job(name: str, resource: str, out: Path, *extra: str) -> Job:
    command = ["uv", "run", "--locked", str(ROOT / "packages" / "game-offscreen" / "offscreen.py"), "--",
               "--path", str(GAME), "-s", "res://tools/models/render_in_game.gd", "--",
               resource, str(out), *extra, "--seed=0"]
    return Job(name, command, out)


def run(command: list[str], log_path: Path, timeout: float) -> int | None:
    """Runs the command into its log; its exit code, or None when it ran out of time. A command
    that runs out is stopped with everything it started (uv's Blender, offscreen.py's Xvfb and
    Godot): it runs in a process group of its own, which gets SIGTERM, then SIGKILL."""
    with log_path.open("w") as output:
        with RUNNING_LOCK:
            if INTERRUPTED.is_set():
                return 130
            process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            RUNNING.add(process)
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            stop(process)
            return None
        except BaseException:
            stop(process)  # Ctrl-C during the import, in the main thread
            raise
        finally:
            with RUNNING_LOCK:
                RUNNING.discard(process)


def stop(process: subprocess.Popen) -> None:
    """Ends the process's group (see stop_all)."""
    stop_all([process])


def stop_all(processes: list[subprocess.Popen]) -> None:
    """Ends every process's group: SIGTERM to all, one shared grace period, then SIGKILL for
    whatever is left, also when a group's leader is already gone and a child of it isn't."""
    for process in processes:
        signal_group(process, signal.SIGTERM)
    deadline = time.monotonic() + GRACE
    for process in processes:
        try:
            process.wait(timeout=max(0.0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            pass
    for process in processes:
        signal_group(process, signal.SIGKILL)
        process.wait()


def signal_group(process: subprocess.Popen, sig: signal.Signals) -> None:
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass


def run_all(blender: list[Job], godot: list[Job], logs: Path, jobs: int, timeout: float) -> dict[str, str]:
    """Runs the Blender jobs one after another beside the Godot jobs, `jobs` of those at once,
    each stopped after `timeout` seconds; the jobs that failed, each with why and its log."""
    failed: dict[str, str] = {}
    lock = threading.Lock()
    starting = threading.Lock()

    def one(job: Job, stagger: bool) -> None:
        if stagger:
            with starting:
                if INTERRUPTED.wait(STAGGER):  # an interrupted run starts nothing new
                    return
        began = time.monotonic()
        log.info(f"{job.name}: rendering into {job.out}")
        code = run(job.command, logs / f"{job.name}.log", timeout)
        with lock:
            if code is None:
                failed[job.name] = f"{job.name} timed out after {timeout:.0f} s, stopped as hung: {logs / (job.name + '.log')}"
                log.error(failed[job.name])
            elif code != 0:
                failed[job.name] = f"{job.name} failed ({code}): {logs / (job.name + '.log')}"
                log.error(failed[job.name])
            else:
                log.info(f"{job.name}: done in {time.monotonic() - began:.0f} s")

    def blender_chain() -> None:
        for job in blender:
            one(job, stagger=False)

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as blender_pool, \
            concurrent.futures.ThreadPoolExecutor(max_workers=max(1, jobs)) as godot_pool:
        futures: list[concurrent.futures.Future] = []
        try:
            futures.append(blender_pool.submit(blender_chain))
            futures += [godot_pool.submit(one, job, True) for job in godot]
            for future in futures:
                future.result()
        except BaseException:
            # Ctrl-C: nothing new starts, and what runs is stopped, else the pools wait for it.
            with RUNNING_LOCK:
                INTERRUPTED.set()
                running = list(RUNNING)
            for pool in (blender_pool, godot_pool):
                pool.shutdown(wait=False, cancel_futures=True)
            stop_all(running)
            raise
    return failed


def collect(out: Path, clips: list[str], quick: bool,
            failed: dict[str, str]) -> tuple[dict[str, Path], dict[str, str]]:
    """The pictures to publish, keyed by what they show: the renders, the six sides joined into
    one picture and every clip's GIFs (the four-frame tiles beside them, not published). And the
    pictures that weren't made, each with why: its job failed (`failed`, by job), or joining its
    frames did, or its file isn't there."""
    desktop = out / "desktop"
    # Each picture's job, the one whose failure leaves it out.
    wanted: dict[str, tuple[str, Path]] = {
        "sheet": ("sheet", out / "sheet" / "sheet.png"),
        "game": ("desktop", desktop / "game.png"),
        "portrait": ("desktop", desktop / "portrait.png"),
        "face": ("desktop", desktop / "face.png"),
        "sides": ("desktop", out / "sides.png"),
    }
    if not quick:
        wanted["phone"] = ("phone", out / "phone" / "game.png")
        wanted["points"] = ("points", out / "points" / "portrait.png")
    for label, job in (("", "clips-game"), ("close-", "clips-close")):
        for clip in clips:
            wanted[f"{label}{clip}"] = (job, out / f"{label}{clip}.gif")
    missing = {key: failed[job] for key, (job, _path) in wanted.items() if job in failed}

    if "sides" not in missing and not ffmpeg(*[desktop / f"{side}.png" for side in SIDES],
                                             filters=sides_filter(), out=wanted["sides"][1]):
        missing["sides"] = f"ffmpeg couldn't join the six sides from {desktop}: {out / 'logs' / 'desktop.log'}"
    (out / "tiles").mkdir(exist_ok=True)
    for view, folder, label in (("game", out / "clips-game", ""), ("close", out / "clips-close", "close-")):
        for clip in clips:
            key = f"{label}{clip}"
            if key in missing:
                continue
            job_log = out / "logs" / f"{folder.name}.log"
            if gif.make(folder, clip, out=wanted[key][1]) is None:
                missing[key] = f"no GIF made from {folder}: {job_log}"
                continue
            frames = sorted(folder.glob(f"{clip}_[0-9][0-9][0-9].png"))
            picked = [frames[round(index * (len(frames) - 1) / 3)] for index in range(4)]
            tile = out / "tiles" / f"{view}-{clip}.png"
            # Not published, but a missing tile still fails the run, listed with the pictures.
            if not ffmpeg(*picked, filters="hstack=inputs=4,scale=1280:-1", out=tile):
                missing[f"tiles/{tile.name}"] = f"ffmpeg couldn't join four frames from {folder}: {job_log}"
    for key, (job, path) in wanted.items():
        if key not in missing and not path.is_file():
            missing[key] = f"{path} wasn't made: {out / 'logs' / (job + '.log')}"
    pictures = {key: path for key, (_job, path) in wanted.items() if key not in missing}
    return pictures, missing


def sides_filter() -> str:
    """Six pictures in two rows of three, each 640 by 360: front, back, left; right, top,
    three-quarter."""
    scaled = ";".join(f"[{index}]scale=640:360[s{index}]" for index in range(6))
    return f"{scaled};[s0][s1][s2]hstack=inputs=3[top];[s3][s4][s5]hstack=inputs=3[bottom];[top][bottom]vstack"


def ffmpeg(*inputs: Path, filters: str, out: Path) -> bool:
    command = ["ffmpeg", "-loglevel", "error", "-y"]
    for path in inputs:
        command += ["-i", str(path)]
    made = subprocess.run([*command, "-filter_complex", filters, "-frames:v", "1", str(out)], check=False)
    if made.returncode != 0:
        log.error(f"ffmpeg couldn't make {out}")
    return made.returncode == 0


def stage(folder: Path, prefix: str, pictures: dict[str, Path]) -> dict[str, Path]:
    """Copies each picture to its published name, `<prefix>-<what>.<ext>`."""
    folder.mkdir(exist_ok=True)
    staged = {}
    for key, path in pictures.items():
        target = folder / f"{prefix}-{key}{path.suffix}"
        target.write_bytes(path.read_bytes())
        staged[key] = target
    return staged


def block(link, clips: list[str], quick: bool, have: set[str]) -> str:
    """The description's media block, in the layout of the recent model pull requests (#1514),
    with only the pictures in `have`: a section none of whose pictures were made is left out."""
    sections = [
        ("**Every side as built** (Blender):", [("sheet", "sheet")]),
        ("**In game, beside the player**" + ("" if quick else " (desktop, then phone)") + ":",
         [("in game", "game")] + ([] if quick else [("phone", "phone")])),
        ("**Close-ups** (portrait, face)" + ("" if quick else ", and its attachment points") + ":",
         [("portrait", "portrait"), ("face", "face")] + ([] if quick else [("points", "points")])),
        ("**Six sides in game** (front, back, left; right, top, three-quarter):", [("sides", "sides")]),
    ]
    lines: list[str] = []
    for heading, pictures in sections:
        shown = [f"![{alt}]({link(key)})" for alt, key in pictures if key in have]
        if not shown:
            continue
        if lines:
            lines.append("")
        lines += [heading, ""]
        for index, picture in enumerate(shown):
            # The in-game shots are paragraphs of their own, the close-ups one row.
            if index and not heading.startswith("**Close-ups**"):
                lines.append("")
            lines.append(picture)
    def cell(key: str) -> str:
        return f"![]({link(key)})" if key in have else "*not rendered*"

    if quick:
        lines += ["", "*Quick renders: the phone, the attachment points and every clip follow.*"]
    elif any(key in have for clip in clips for key in (clip, "close-" + clip)):
        lines += [
            "",
            "**Every clip**, in game (game camera) and close (three-quarter):",
            "",
            "| Clip | In game | Close |",
            "| --- | --- | --- |",
        ]
        lines += [f"| **{clip}** | {cell(clip)} | {cell('close-' + clip)} |" for clip in clips]
    return "\n".join(lines)


if __name__ == "__main__":
    sys.exit(main())
