"""Renders a model's pictures for its pull request in one command (#1525), publishes them on the
assets branch and prints the description's media block, ready to paste.

    uv run --locked --package khovax-game-models packages/game-models/render_media.py \
        packages/game/assets/<name>/<name>.glb --pr <n> [--tag v2] [--quick] [--out <folder>] \
        [--jobs 3] [--no-publish]

It runs what a model pull request shows (the model skill's step 5), Blender (GPU) and Godot (CPU)
side by side, and Godot only off the desktop, through offscreen.py:
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
Godot project is imported first, so the renders never show a stale import (#1164). Each job's log
is in `<out>/logs/`; a job that fails stops the run before anything is published."""

import argparse
import concurrent.futures
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
    parser.add_argument("--out", type=Path, help="where to render (a temporary folder by default)")
    parser.add_argument("--jobs", type=int, default=3, help="Godot renders at once")
    parser.add_argument("--no-publish", action="store_true", help="render only, print local paths")
    args = parser.parse_args()

    model = args.model.resolve()
    if not model.is_file() or GAME not in model.parents:
        log.error(f"{args.model}: no .glb inside {GAME.relative_to(ROOT)}, where Godot can load it")
        return 1
    prefix = f"pr-{args.pr}" + (f"-{args.tag}" if args.tag else "")
    out = (args.out or Path(tempfile.gettempdir()) / f"khovax-media-{prefix}").resolve()
    (out / "logs").mkdir(parents=True, exist_ok=True)
    clips = [] if args.quick else clips_of(model)
    resource = "res://" + model.relative_to(GAME).as_posix()

    log.info("importing the game project, so the renders show this build")
    if run(["godot", "--headless", "--path", str(GAME), "--import"], out / "logs" / "import.log") != 0:
        log.error(f"the import failed: {out / 'logs' / 'import.log'}")
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
    if not run_all(blender, godot, out / "logs", args.jobs):
        return 1

    pictures = collect(out, clips, args.quick)
    if pictures is None:
        return 1
    staged = stage(out / "publish", prefix, pictures)
    if not args.no_publish:
        published = subprocess.run(
            ["uv", "run", "--locked", "--package", "khovax-game-visuals",
             str(ROOT / "packages" / "game-visuals" / "publish.py"), *map(str, staged.values())],
            cwd=ROOT, check=False,
        )
        if published.returncode != 0:
            log.error("publishing failed")
            return 1
    link = (lambda key: URL.format(staged[key].name)) if not args.no_publish else (lambda key: str(staged[key]))
    if clips:
        log.info(f"pose sheets: {out / 'poses'}; four-frame tiles: {out / 'tiles'}")
    print("\n----- media block -----\n")
    print(block(link, clips, args.quick))
    return 0


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


def run(command: list[str], log_path: Path) -> int:
    with log_path.open("w") as output:
        return subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=False).returncode


def run_all(blender: list[Job], godot: list[Job], logs: Path, jobs: int) -> bool:
    """Runs the Blender jobs one after another beside the Godot jobs, `jobs` of those at once;
    True when every one of them succeeded."""
    failed: list[str] = []
    lock = threading.Lock()
    starting = threading.Lock()

    def one(job: Job, stagger: bool) -> None:
        if stagger:
            with starting:
                time.sleep(STAGGER)
        began = time.monotonic()
        log.info(f"{job.name}: rendering into {job.out}")
        code = run(job.command, logs / f"{job.name}.log")
        with lock:
            if code != 0:
                failed.append(job.name)
                log.error(f"{job.name} failed ({code}): {logs / (job.name + '.log')}")
            else:
                log.info(f"{job.name}: done in {time.monotonic() - began:.0f} s")

    def blender_chain() -> None:
        for job in blender:
            one(job, stagger=False)

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as blender_pool, \
            concurrent.futures.ThreadPoolExecutor(max_workers=max(1, jobs)) as godot_pool:
        futures = [blender_pool.submit(blender_chain)]
        futures += [godot_pool.submit(one, job, True) for job in godot]
        for future in futures:
            future.result()
    return not failed


def collect(out: Path, clips: list[str], quick: bool) -> dict[str, Path] | None:
    """The pictures to publish, keyed by what they show: the renders, the six sides joined into
    one picture and every clip's GIFs (the four-frame tiles beside them, not published)."""
    desktop = out / "desktop"
    pictures = {
        "sheet": out / "sheet" / "sheet.png",
        "game": desktop / "game.png",
        "portrait": desktop / "portrait.png",
        "face": desktop / "face.png",
        "sides": out / "sides.png",
    }
    if not ffmpeg(*[desktop / f"{side}.png" for side in SIDES], filters=sides_filter(), out=pictures["sides"]):
        return None
    if not quick:
        pictures["phone"] = out / "phone" / "game.png"
        pictures["points"] = out / "points" / "portrait.png"
    (out / "tiles").mkdir(exist_ok=True)
    for view, folder, label in (("game", out / "clips-game", ""), ("close", out / "clips-close", "close-")):
        for clip in clips:
            made = gif.make(folder, clip, out=out / f"{label}{clip}.gif")
            if made is None:
                return None
            pictures[f"{label}{clip}"] = made
            frames = sorted(folder.glob(f"{clip}_[0-9][0-9][0-9].png"))
            picked = [frames[round(index * (len(frames) - 1) / 3)] for index in range(4)]
            if not ffmpeg(*picked, filters="hstack=inputs=4,scale=1280:-1", out=out / "tiles" / f"{view}-{clip}.png"):
                return None
    missing = [str(path) for path in pictures.values() if not path.is_file()]
    if missing:
        log.error(f"not rendered: {', '.join(missing)}")
        return None
    return pictures


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


def block(link, clips: list[str], quick: bool) -> str:
    """The description's media block, in the layout of the recent model pull requests (#1514)."""
    lines = [
        "**Every side as built** (Blender):",
        "",
        f"![sheet]({link('sheet')})",
        "",
        "**In game, beside the player**" + ("" if quick else " (desktop, then phone)") + ":",
        "",
        f"![in game]({link('game')})",
    ]
    if not quick:
        lines += ["", f"![phone]({link('phone')})"]
    lines += [
        "",
        "**Close-ups** (portrait, face)" + ("" if quick else ", and its attachment points") + ":",
        "",
        f"![portrait]({link('portrait')})",
        f"![face]({link('face')})",
    ]
    if not quick:
        lines.append(f"![points]({link('points')})")
    lines += [
        "",
        "**Six sides in game** (front, back, left; right, top, three-quarter):",
        "",
        f"![sides]({link('sides')})",
    ]
    if quick:
        lines += ["", "*Quick renders: the phone, the attachment points and every clip follow.*"]
    elif clips:
        lines += [
            "",
            "**Every clip**, in game (game camera) and close (three-quarter):",
            "",
            "| Clip | In game | Close |",
            "| --- | --- | --- |",
        ]
        lines += [f"| **{clip}** | ![]({link(clip)}) | ![]({link('close-' + clip)}) |" for clip in clips]
    return "\n".join(lines)


if __name__ == "__main__":
    sys.exit(main())
