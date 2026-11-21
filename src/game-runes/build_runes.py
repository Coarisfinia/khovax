"""Draws our own rune script (#1855) from its data into one SVG per glyph and the sheet of the
whole set, each glyph with its letter under it. The runes come entirely from the default resource
pack (the owner, on #2593), so a pack can replace the script: the glyphs lie in
resourcepacks/default/runes/khovax-runes/, which the pack's manifest lists under `runes`, and their
data (runes.json) and the sheet in its build/ folder, which Godot never sees (.gdignore).

AI-drawn runes come out sloppy, each glyph different, so the script is drawn from data the way the
starry sky is (#1635): every glyph is a few straight strokes of one width between points of one
shared grid, with one fixed height. The data is the source; the SVGs are written from it, byte for
byte the same on every machine, and `--check` fails when a committed one no longer matches.

    uv run --locked --package khovax-game-runes src/game-runes/build_runes.py [--check]
"""

import argparse
import json
import sys
from pathlib import Path

# The runes' folder in the default pack, and its build folder beside the glyphs.
PACK = Path(__file__).resolve().parents[2] / "resourcepacks" / "default" / "runes" / "khovax-runes"
BUILD = PACK / "build"
DATA = BUILD / "runes.json"
INK = "#2b2118"
PAPER = "#efe6d2"
FAINT = "#7a6a55"
# The sheet: grid units in pixels for the set, and for the small sample that shows the glyphs
# still read at prop size (16 px tall).
SCALE = 10
SMALL = 2
CELL_W, CELL_H = 80, 132
COLUMNS = 13
MARGIN = 30
# Glyph names shown under a sign whose character alone would be hard to read on the sheet.
SIGN_NAMES = {" ": "gap", "'": "'", ".": ".", ",": ",", "-": "-", "/": "/"}
SAMPLES = ("kel vis dar ol osk sel", "kel'varun", "khovax - 2026, 1/9.")


def num(value: float) -> str:
    """A coordinate as the shortest exact text, so the output is the same on every machine."""
    text = f"{value:.3f}".rstrip("0").rstrip(".")
    return "0" if text == "-0" else text


def strokes_svg(strokes, dx: float, dy: float, scale: float, width: float) -> list[str]:
    """Each stroke as an SVG path of straight lines, moved by (dx, dy) and scaled, in grid units."""
    lines = []
    for stroke in strokes:
        points = " L".join(f"{num(dx + x * scale)} {num(dy + y * scale)}" for x, y in stroke)
        lines.append(
            f'<path d="M{points}" fill="none" stroke="{INK}" stroke-width="{num(width)}"'
            ' stroke-linecap="round" stroke-linejoin="round"/>'
        )
    return lines


def glyph_svg(glyph: dict, grid: dict) -> str:
    """One glyph alone, in grid units, its box the grid's height and its own width, plus half a
    stroke around so the round ends aren't cut."""
    pad = grid["stroke"] / 2
    w, h = glyph["width"] + 2 * pad, grid["height"] + 2 * pad
    body = strokes_svg(glyph["strokes"], pad, pad, 1, grid["stroke"])
    return "\n".join(
        [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {num(w)} {num(h)}"'
            f' width="{num(w * 8)}" height="{num(h * 8)}">',
            *body,
            "</svg>",
            "",
        ]
    )


def text_svg(text: str, glyphs: dict, grid: dict, x: float, y: float, scale: float) -> list[str]:
    """A text written in the runes, letter for letter, from (x, y) at `scale` pixels a unit."""
    lines = []
    for char in text:
        glyph = glyphs[char]
        lines += strokes_svg(glyph["strokes"], x, y, scale, grid["stroke"] * scale)
        x += (glyph["width"] + grid["spacing"]) * scale
    return lines


def label(x: float, y: float, text: str, size: int, colour: str = FAINT) -> str:
    escaped = text.replace("&", "&amp;").replace("<", "&lt;")
    return (
        f'<text x="{num(x)}" y="{num(y)}" font-family="DejaVu Sans, sans-serif" font-size="{size}"'
        f' fill="{colour}" text-anchor="middle">{escaped}</text>'
    )


def sheet_svg(data: dict) -> str:
    """The whole set in rows (letters, digits, signs), each glyph over its character, then sample
    words in the runes at the sheet's size and at prop size."""
    grid = data["grid"]
    glyphs = {glyph["char"]: glyph for glyph in data["glyphs"]}
    groups = [
        [g for g in data["glyphs"] if g["char"].isalpha()],
        [g for g in data["glyphs"] if g["char"].isdigit()],
        [g for g in data["glyphs"] if not g["char"].isalnum()],
    ]
    rows = [group[i : i + COLUMNS] for group in groups for i in range(0, len(group), COLUMNS)]
    width = 2 * MARGIN + COLUMNS * CELL_W
    body, y = [], MARGIN
    for row in rows:
        for column, glyph in enumerate(row):
            left = MARGIN + column * CELL_W
            body.append(
                f'<rect x="{left + 4}" y="{y}" width="{CELL_W - 8}" height="{CELL_H - 8}"'
                f' fill="none" stroke="{FAINT}" stroke-opacity="0.25" stroke-dasharray="3 3"/>'
            )
            gx = left + (CELL_W - glyph["width"] * SCALE) / 2
            body += strokes_svg(glyph["strokes"], gx, y + 12, SCALE, grid["stroke"] * SCALE)
            name = SIGN_NAMES.get(glyph["char"], glyph["char"].upper())
            body.append(label(left + CELL_W / 2, y + CELL_H - 18, name, 18, INK))
        y += CELL_H
    for text in SAMPLES:
        y += 14
        body.append(label(width / 2, y + 4, f"“{text}”", 14))
        y += 14
        for scale in (4, SMALL):
            # The ink's width: the spacing after the last glyph isn't part of it.
            run = sum((glyphs[c]["width"] + grid["spacing"]) * scale for c in text)
            run -= grid["spacing"] * scale
            body += text_svg(text, glyphs, grid, (width - run) / 2, y, scale)
            y += grid["height"] * scale + 12
    height = y + MARGIN
    return "\n".join(
        [
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {num(height)}"'
            f' width="{width}" height="{num(height)}">',
            f'<rect width="{width}" height="{num(height)}" fill="{PAPER}"/>',
            *body,
            "</svg>",
            "",
        ]
    )


def outputs(data: dict) -> dict[Path, str]:
    files = {PACK / f"{g['file']}.svg": glyph_svg(g, data["grid"]) for g in data["glyphs"]}
    files[BUILD / "sheet.svg"] = sheet_svg(data)
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description="Draw the rune SVGs from runes.json.")
    parser.add_argument("--check", action="store_true", help="fail when a committed SVG is stale")
    args = parser.parse_args()
    data = json.loads(DATA.read_text(encoding="utf-8"))
    files = outputs(data)
    if args.check:
        stale = [p for p, text in files.items() if not p.is_file() or p.read_text("utf-8") != text]
        stray = set(PACK.glob("*.svg")) - set(files)
        for path in sorted(stale) + sorted(stray):
            print(f"{path.relative_to(PACK)}: stale, run build_runes.py", file=sys.stderr)
        return 1 if stale or stray else 0
    for path, text in files.items():
        path.write_text(text, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
