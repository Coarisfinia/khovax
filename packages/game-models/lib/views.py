"""How the game's views show a pack's model on the board (#1652), read from the views themselves for
check_footprint.py: a pack's model (the players' and people's figure, the chest) has no script in
packages/game-models/, and its .glb isn't at the size the game shows it, since the view that puts it
on a tile sizes it.

A **view** of a model is a script in a slice's `look/` whose `MODEL` constant is the model's id in
the default resource pack (#1864: `const MODEL: String = "model_chest"`, or another view's
`PlayerView.MODEL`), the pack's manifest mapping the id to its .glb: CI reruns the check when
either changes. From it come, each from a constant of that name in the view, or the one of another
script it uses as `Class.NAME` (a value may name another constant too, in the view or as
`Class.NAME`):

- `MODEL_SCALE`: the scale it draws the model at (1 without one);
- `CLIPS`: the clips it plays (every clip without one, an empty list for none);
- `IDLE`: the clip it stands in, measured in place of the rest pose (a figure's is a T-pose);
- `HIDDEN_PARTS`: the parts it hides (the figure's weapons), left out of the measure.

A model no view names isn't put on the board (the items, shown only in the gear
panel's pictures) and has no views."""

import glob
import os
import re
from pathlib import Path

from game_shared.resource_packs import MANIFEST, models, read_manifest, section

# A constant: its name and the text after its `=`, which may run on over lines until its brackets
# close.
CONST = re.compile(r"^const\s+(\w+)\b[^=\n]*=\s*", re.M)
CLASS = re.compile(r"^class_name\s+(\w+)", re.M)


class View:
    """How one view shows a model: `name` (the view's script), `scale`, `clips`, `standing` (a
    clip, or None) and `hidden` (part names)."""

    def __init__(self, name, scale, clips, standing, hidden):
        self.name, self.scale, self.clips, self.standing, self.hidden = name, scale, clips, standing, hidden

    def key(self):
        clips = None if self.clips is None else tuple(self.clips)
        return (self.scale, clips, self.standing, tuple(sorted(self.hidden)))


class Scripts:
    """The game's scripts under `game` (the Godot project's folder), their constants read on
    demand."""

    def __init__(self, game):
        self.game = game
        self.paths = sorted(
            path for path in glob.glob(os.path.join(game, "**", "*.gd"), recursive=True)
            if not _skipped(game, path))
        self.texts = {}
        self.classes = {}
        for path in self.paths:
            found = CLASS.search(self.text(path))
            if found:
                self.classes[found.group(1)] = path

    def text(self, path):
        if path not in self.texts:
            with open(path, encoding="utf-8") as source:
                self.texts[path] = source.read()
        return self.texts[path]

    def const(self, path, name, default=None):
        """The value of constant `name` in the script at `path`, or `default` without one."""
        for found in CONST.finditer(self.text(path)):
            if found.group(1) == name:
                return self.value(path, _expression(self.text(path), found.end()))
        return default

    def value(self, path, text):
        """The value of the expression `text` in the script at `path`: a number, a string or
        StringName, a list of them, or a constant's name, its own or `Class.NAME`."""
        text = text.strip().rstrip(",").strip()
        if text.startswith("["):
            return [self.value(path, item) for item in _items(text[1:-1])]
        string = re.fullmatch(r'&?"([^"]*)"', text)
        if string:
            return string.group(1)
        if re.fullmatch(r"-?\d+(\.\d*)?", text):
            return float(text)
        other = re.fullmatch(r"(\w+)\.(\w+)", text)
        if other and other.group(1) in self.classes:
            return self._named(self.classes[other.group(1)], other.group(2))
        if re.fullmatch(r"\w+", text):
            return self._named(path, text)
        raise ValueError("%s: can't read %r" % (_short(self.game, path), text))

    def _named(self, path, name):
        value = self.const(path, name)
        if value is None:
            raise ValueError("%s has no constant %s" % (_short(self.game, path), name))
        return value

    def setting(self, path, name, default=None):
        """The view's constant `name`: its own, or another script's it uses (NpcView hides
        `PlayerView.HIDDEN_PARTS`), else `default`."""
        own = self.const(path, name)
        if own is not None:
            return own
        for found in re.finditer(r"\b(\w+)\.%s\b" % name, self.text(path)):
            if found.group(1) in self.classes:
                return self._named(self.classes[found.group(1)], name)
        return default

    def view(self, path):
        """How the script at `path` shows its model."""
        return View(
            os.path.splitext(os.path.basename(path))[0],
            self.setting(path, "MODEL_SCALE", 1.0),
            self.setting(path, "CLIPS"),
            self.setting(path, "IDLE"),
            self.setting(path, "HIDDEN_PARTS", []))


def find(game, model, scripts=None):
    """Every distinct view that shows the .glb named `model` (without its extension) on the board,
    in the Godot project at `game`. Raises ValueError where a view can't be read."""
    scripts = scripts or Scripts(game)
    ids = model_ids(game, model)
    looks = os.path.join(game, "slices", "*", "look", "**", "*.gd")
    views = [
        scripts.view(path) for path in sorted(glob.glob(looks, recursive=True))
        if scripts.const(path, "MODEL") in ids]
    distinct = {}
    for view in views:
        distinct.setdefault(view.key(), view)
    return list(distinct.values())


def decorations(game):
    """The names (.glb or .gltf without the extension) of the models the tile blueprints of the
    Godot project at `game` name as their decoration (TileDecorations shows it): the tile's own
    look, sized to its tile, not a thing standing on it."""
    # A tile names its model's id in the default resource pack, whose manifest gives its file
    # (#1864), and the tiles' own files too (#1901).
    manifest = read_manifest(Path(game) / MANIFEST)
    pack_models = models(manifest)
    tiles = sorted(section(manifest, "tiles").values())
    names = set()
    for path in tiles:
        with open(os.path.join(game, path), encoding="utf-8") as text:
            # JSONC: a commented-out model names no decoration. A comment starts after a space or
            # at a line's start, never in a path's `res://`.
            body = re.sub(r"(?m)(^|\s)//.*$", "", re.sub(r"/\*.*?\*/", "", text.read(), flags=re.S))
            for found in re.finditer(r'"model"\s*:\s*"([^"]+)"', body):
                names.add(os.path.splitext(os.path.basename(pack_models[found.group(1)]))[0])
    if not names:
        raise ValueError("no tile blueprint the default pack lists names a model: %s" % tiles)
    return names


def model_ids(game, model):
    """The ids the default resource pack gives the .glb named `model` (without its extension)."""
    path = os.path.join(game, MANIFEST)
    return {
        model_id for model_id, file in models(read_manifest(Path(path))).items()
        if os.path.splitext(os.path.basename(file))[0] == model}


def _expression(text, start):
    """The constant's value from `start`: up to the line's end, or past it while brackets are open,
    without its comments (a `#` outside a string, at any depth)."""
    depth, end, quoted, kept = 0, start, False, []
    while end < len(text):
        char = text[end]
        if char == '"':
            quoted = not quoted
        elif not quoted:
            if char == "#":
                while end < len(text) and text[end] != "\n":
                    end += 1
                continue
            if char in "([{":
                depth += 1
            elif char in ")]}":
                depth -= 1
            elif char == "\n" and depth <= 0:
                break
        kept.append(char)
        end += 1
    return "".join(kept)


def _items(text):
    """A list's items, split at its top-level commas outside strings."""
    items, depth, quoted, item = [], 0, False, ""
    for char in text:
        if char == '"':
            quoted = not quoted
        elif not quoted:
            depth += char in "([{"
            depth -= char in ")]}"
        if char == "," and depth == 0 and not quoted:
            items.append(item)
            item = ""
        else:
            item += char
    items.append(item)
    return [item for item in items if item.strip()]


def _skipped(game, path):
    """Whether `path` is outside the game's own views: Godot's cache, the tests and the tools."""
    parts = os.path.relpath(path, game).split(os.sep)
    return parts[0] in (".godot", "tests", "tools", "addons")


def _short(game, path):
    return os.path.relpath(path, game)
