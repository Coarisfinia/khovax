"""Makes a clip's GIF from its frames (model skill, #1050): the frames `render_in_game.gd` writes
for a clip (`<Clip>_000.png`, `<Clip>_001.png`, ...), through ffmpeg's palette pass, which is
faster and smaller than ImageMagick, looping forever.

    uv run --locked packages/game-models/gif.py <frame_dir> <Clip> [--fps 15] [--width 640] \
        [--out <file.gif>]

It writes `<frame_dir>/<Clip>.gif` unless `--out` says otherwise, and prints its path."""

import argparse
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="A clip's GIF from its frames.")
    parser.add_argument("frame_dir", type=Path)
    parser.add_argument("clip")
    # render_in_game.gd's CLIP_FPS: the frames play back at the rate they were captured.
    parser.add_argument("--fps", type=float, default=15.0)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    # Only the numbered frames, in order from the first: ffmpeg reads the sequence until a gap, so
    # another image named like the clip never ends up in it.
    first = args.frame_dir / f"{args.clip}_000.png"
    if not first.is_file():
        print(f"no frames: {first} is missing", file=sys.stderr)
        return 1
    frames = str(args.frame_dir / f"{args.clip.replace('%', '%%')}_%03d.png")
    out = args.out or args.frame_dir / f"{args.clip}.gif"
    # One pass makes the GIF's palette from all frames, the second maps every frame onto it.
    palette = f"scale={args.width}:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"
    made = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(args.fps),
         "-start_number", "0", "-i", frames, "-vf", palette, "-loop", "0", str(out)],
        check=False,
    )
    if made.returncode != 0:
        return made.returncode
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
