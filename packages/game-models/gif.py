"""Makes a clip's GIF from its frames (model skill, #1050): the frames `render_in_game.gd` writes
for a clip (`<Clip>_000.png`, `<Clip>_001.png`, ...), at the rate it captured them (`<Clip>.fps`
beside them, the clip's own, #1150), through ffmpeg's palette pass, which is
faster and smaller than ImageMagick, looping forever.

    uv run --locked packages/game-models/gif.py <frame_dir> <Clip> [--fps <rate>] [--width 640] \
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
    # By default the frames play back at the rate render_in_game.gd captured them at (#1150).
    parser.add_argument("--fps", type=float)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    made = make(args.frame_dir, args.clip, args.fps, args.width, args.out)
    if made is None:
        return 1
    print(made)
    return 0


def make(frame_dir: Path, clip: str, fps: float | None = None, width: int = 640,
         out: Path | None = None) -> Path | None:
    """Writes the clip's GIF (`out`, else `<frame_dir>/<Clip>.gif`) and returns its path, or None
    when its frames, its rate or ffmpeg fail, after saying why on stderr. render_media.py makes
    every clip's GIF through it (#1525)."""
    # Only the numbered frames, in order from the first: ffmpeg reads the sequence until a gap, so
    # another image named like the clip never ends up in it.
    first = frame_dir / f"{clip}_000.png"
    if not first.is_file():
        print(f"no frames: {first} is missing", file=sys.stderr)
        return None
    if fps is None:
        rate = frame_dir / f"{clip}.fps"
        if not rate.is_file():
            print(f"no rate: {rate} is missing, so pass --fps", file=sys.stderr)
            return None
        try:
            fps = float(rate.read_text().strip())
        except ValueError:
            fps = 0.0
    if not 0.0 < fps < float("inf"):
        print(f"no rate: {fps} is not a frame rate", file=sys.stderr)
        return None
    frames = str(frame_dir / f"{clip.replace('%', '%%')}_%03d.png")
    out = out or frame_dir / f"{clip}.gif"
    # One pass makes the GIF's palette from all frames, the second maps every frame onto it.
    palette = f"scale={width}:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"
    made = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(fps),
         "-start_number", "0", "-i", frames, "-vf", palette, "-loop", "0", str(out)],
        check=False,
    )
    if made.returncode != 0:
        print(f"ffmpeg failed on {clip}'s frames ({made.returncode})", file=sys.stderr)
        return None
    return out

if __name__ == "__main__":
    sys.exit(main())
