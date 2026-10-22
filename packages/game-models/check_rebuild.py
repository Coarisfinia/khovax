"""Checks that a model script builds the same file every time (#1085): it builds the model twice,
side by side, and compares the two .glb files byte for byte; with the committed .glb, it compares
that too, which tells whether a pull request's .glb is what its script builds.

    uv run --locked --package khovax-game-models packages/game-models/check_rebuild.py \
        packages/game-models/<name>.py \
        [packages/game/assets/<name>/<name>.glb]
    uv run --locked --package khovax-game-models packages/game-models/check_rebuild.py --all

`--all` checks every scripted model against its committed .glb, as CI does (#1161): a model
script is one here that exports through scene.export_glb, and its .glb is the tracked one under
the game's assets/ named like it (mana_wolf.py builds assets/mana-wolf/mana_wolf.glb); a model
script without one fails.
It prints `REBUILD CHECK: PASS` or `FAIL`. On a difference it names what differs, the JSON part
(nodes, materials, ...) or each binary accessor (a mesh's indices or attribute, a clip's
channel) with how many values differ and by how much: indices that only move point to the order
of faces, values off by a hair to float noise. A script builds into the path after its `--`, as
every model script does. It reports through game_shared.log (#1115): in CI, a difference is an
error annotation on the committed .glb."""

import json
import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from game_shared import log
from game_shared.git_files import git_files

MODELS = Path(__file__).resolve().parent
BLENDER = MODELS / "blender.py"
# A model script's export call, as a statement of its own.
EXPORT = re.compile(r"^\s*scene\.export_glb\(", re.MULTILINE)
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
FORMATS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}


def build(script: Path, out: Path, output: Path) -> subprocess.Popen:
    command = [sys.executable, str(BLENDER), "--background", "--factory-startup", "--python", str(script),
               "--", str(out)]
    return subprocess.Popen(command, stdout=output.open("w"), stderr=subprocess.STDOUT)


def read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    json_length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + json_length])
    start = 20 + json_length
    binary_length = struct.unpack_from("<I", data, start)[0]
    return gltf, data[start + 8:start + 8 + binary_length]


def accessor_names(gltf: dict) -> dict[int, str]:
    names = {}
    for mesh in gltf.get("meshes", []):
        for index, primitive in enumerate(mesh["primitives"]):
            for attribute, accessor in primitive["attributes"].items():
                names[accessor] = f"mesh {mesh.get('name')} #{index} {attribute}"
            if "indices" in primitive:
                names[primitive["indices"]] = f"mesh {mesh.get('name')} #{index} indices"
    for animation in gltf.get("animations", []):
        for index, sampler in enumerate(animation["samplers"]):
            names.setdefault(sampler["input"], f"clip {animation.get('name')} times")
            names[sampler["output"]] = f"clip {animation.get('name')} channel {index}"
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            names[skin["inverseBindMatrices"]] = "skin inverse bind matrices"
    return names


def values(gltf: dict, binary: bytes, accessor: dict) -> tuple:
    view = gltf["bufferViews"][accessor["bufferView"]]
    count = accessor["count"] * WIDTHS[accessor["type"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return struct.unpack_from(f"<{count}{FORMATS[accessor['componentType']]}", binary, start)


def differences(a: Path, b: Path) -> list[str]:
    """What differs between two .glb files, one line each; nothing when they're the same bytes."""
    if a.read_bytes() == b.read_bytes():
        return []
    (gltf_a, binary_a), (gltf_b, binary_b) = read_glb(a), read_glb(b)
    lines = [f"JSON {key} differs" for key in sorted(gltf_a.keys() | gltf_b.keys())
             if key != "bufferViews" and gltf_a.get(key) != gltf_b.get(key)]
    if lines:
        return lines
    names = accessor_names(gltf_a)
    for index, (accessor_a, accessor_b) in enumerate(zip(gltf_a["accessors"], gltf_b["accessors"])):
        if "bufferView" not in accessor_a:
            continue
        values_a, values_b = values(gltf_a, binary_a, accessor_a), values(gltf_b, binary_b, accessor_b)
        off = [abs(x - y) for x, y in zip(values_a, values_b) if x != y]
        if off:
            moved = " (the same values, reordered)" if sorted(values_a) == sorted(values_b) else ""
            lines.append(f"accessor {index}, {names.get(index, '?')}: {len(off)} of {len(values_a)} values "
                         f"differ, by up to {max(off):g}{moved}")
    return lines or ["the bytes differ outside the accessors (the JSON's layout or padding)"]


def scripted_models() -> list[tuple[str, str | None]]:
    """Every model script with the .glb it builds, both from the working directory: a model script
    is a script here that exports through scene.export_glb, and its .glb is the tracked one under
    the game's assets/ named like it (None when there is none)."""
    glbs = {Path(path).stem: path for path in git_files(str(MODELS.parent / "game" / "assets" / "*.glb"))}
    return [(os.path.relpath(script), glbs.get(script.stem)) for script in sorted(MODELS.glob("*.py"))
            if EXPORT.search(script.read_text())]


def check(script_path: str, committed: Path | None) -> bool:
    """Builds the script twice and compares the builds, and the committed .glb when there is one;
    true when they're all the same bytes."""
    script = Path(script_path).resolve()
    with tempfile.TemporaryDirectory(prefix="check_rebuild_") as scratch:
        outs = [Path(scratch) / f"build{index}.glb" for index in (1, 2)]
        outputs = [Path(scratch) / f"build{index}.log" for index in (1, 2)]
        runs = [build(script, out, output) for out, output in zip(outs, outputs)]
        try:
            codes = [run.wait() for run in runs]
        finally:
            # Neither build outlives the scratch folder, also when this is interrupted.
            for run in runs:
                if run.poll() is None:
                    run.kill()
                    run.wait()
        for code, output, out in zip(codes, outputs, outs):
            if code != 0 or not out.is_file():
                print(output.read_text(), end="")
                log.error(f"{script.name} didn't build", script_path)
                return False
        same = True
        pairs = [(f"{script.name}: the two builds", outs[0], outs[1], script_path)]
        if committed is not None:
            pairs.append((f"{script.name}: the build and {committed}", outs[0], committed, str(committed)))
        for label, a, b, file in pairs:
            lines = differences(a, b)
            if not lines:
                log.info(f"{label}: the same bytes")
                continue
            log.error(f"{label} differ:\n" + "\n".join(f"  {line}" for line in lines), file)
            same = False
    return same


def main() -> int:
    if sys.argv[1:] == ["--all"]:
        models = scripted_models()
        unpaired = [script for script, glb in models if glb is None]
        for script in unpaired:
            # A renamed or deleted .glb would otherwise leave its model unchecked.
            log.error("no tracked .glb under the game's assets/ is named like this model script", script)
        if not models or unpaired:
            if not models:
                log.error("no model script calls scene.export_glb: nothing to check")
            return 1
    elif len(sys.argv) in (2, 3) and sys.argv[1] != "--all":
        models = [(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else None)]
    else:
        print(__doc__, file=sys.stderr)
        return 2
    # Every model is checked, so one failure doesn't hide another's.
    results = [check(script, None if glb is None else Path(glb)) for script, glb in models]
    passed = all(results)
    log.info("REBUILD CHECK: " + ("PASS" if passed else "FAIL"))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
