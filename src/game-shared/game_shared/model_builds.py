"""Where a scripted model's build files lie (#2438): its model script and the sources it builds
from are in the model's own folder in the pack, in `build/` beside the .glb it builds
(resourcepacks/default/models/mana-wolf/build/mana_wolf.py builds
resourcepacks/default/models/mana-wolf/mana_wolf.glb). So a model's folder holds all of it, the way
a player's pack would. The script is named after its .glb, which pairs the two, also in a folder
of two models (the player's body and clips). Its imported source is `build/source.glb`; the
player's clip library keeps its skeleton and clip sources there too.

Godot never sees a build folder: its `.gdignore` (GDIGNORE) keeps Godot from importing, listing
or exporting what is in it, so the shipped game doesn't carry it. The shared model library, the
checks and the import tools stay in src/game-models/.

Blender's own Python imports this too (the model checks), so it needs nothing but the standard
library."""

import os
import re

# A model's build folder, beside its .glb.
BUILD = "build"
# The file in each build folder that keeps Godot out of it.
GDIGNORE = ".gdignore"
# A build folder's path, from the root or from the game's project (through its link).
BUILD_FOLDER = re.compile(r"^resourcepacks/[^/]+/models/[^/]+/" + BUILD + "/")
# A model script's export call, as a statement of its own: a script in a build folder without one
# builds nothing.
EXPORT = re.compile(r"^\s*scene\.export_glb\(", re.MULTILINE)


def is_build_file(path: str) -> bool:
    """Whether a path (from the root, or the game's through its link) lies in a model's build folder."""
    return bool(BUILD_FOLDER.match(path))


def build_script(glb: str) -> str:
    """The model script that would build the .glb at `glb`: build/<name>.py beside it. It may not
    exist (a model that isn't scripted)."""
    folder, name = os.path.split(glb)
    return os.path.join(folder, BUILD, os.path.splitext(name)[0] + ".py")


def built_glb(script: str) -> str:
    """The .glb the model script at `script` builds: its name, beside its build folder."""
    build, name = os.path.split(script)
    return os.path.join(os.path.dirname(build), os.path.splitext(name)[0] + ".glb")


def is_model_script(path: str) -> bool:
    """Whether the file at `path` is a model script: a .py right in a build folder that exports
    through scene.export_glb. A missing file isn't one."""
    parent = os.path.basename(os.path.dirname(path))
    if parent != BUILD or not path.endswith(".py") or not os.path.isfile(path):
        return False
    with open(path, encoding="utf-8") as script:
        return bool(EXPORT.search(script.read()))
