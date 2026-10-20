"""Makes a clip's GIF from its frames (model skill, #1050): the frames `render_in_game.gd` writes
for a clip (`<Clip>_000.png`, `<Clip>_001.png`, ...), through ffmpeg's palette pass, which is
faster and smaller than ImageMagick, looping forever.

    uv run tools/models/gif.py <frame_dir> <Clip> [--fps 15] [--width 640] [--out <file.gif>]

It writes `<frame_dir>/<Clip>.gif` unless `--out` says otherwise, and prints its path."""

import argparse
import glob
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
    pattern = str(args.frame_dir / f"{glob.escape(args.clip)}_*.png")
    if not glob.glob(pattern):
        print(f"no frames match {pattern}", file=sys.stderr)
        return 1
    out = args.out or args.frame_dir / f"{args.clip}.gif"
    # One pass makes the GIF's palette from all frames, the second maps every frame onto it.
    palette = f"scale={args.width}:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"
    made = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(args.fps),
         "-pattern_type", "glob", "-i", pattern, "-vf", palette, "-loop", "0", str(out)],
        check=False,
    )
    if made.returncode != 0:
        return made.returncode
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
