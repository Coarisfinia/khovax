"""How the game's views show a pack's model on the board (#1652), read from the views themselves for
check_footprint.py: a pack's model (the players' and people's figure, the chest) has no script in
packages/game-models/, and its .glb isn't at the size the game shows it, since the view that puts it
on a tile sizes it.

A **view** of a model is a script in a slice's `look/` that preloads its .glb
(`preload("res://…/chest.glb")`), or the script on the node a scene instances it under (main.tscn's
player): CI reruns the check when either changes. From it come, each from a
constant of that name in the view, or the one of another script it uses as `Class.NAME` (a value
may name another constant too, in the view or as `Class.NAME`):

- `MODEL_SCALE`: the scale it draws the model at (1 without one), times the instance's own scale in
  a scene;
- `CLIPS`: the clips it plays (every clip without one, an empty list for none);
- `IDLE`: the clip it stands in, measured in place of the rest pose (a figure's is a T-pose);
- `HIDDEN_PARTS`: the parts it hides (the figure's weapons), left out of the measure.

A model no view preloads or instances isn't put on the board (the items, shown only in the gear
panel's pictures) and has no views."""

import glob
import math
import os
import re

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

    def view(self, path, scale=1.0):
        """How the script at `path` shows its model, times `scale` from the scene it's in."""
        return View(
            os.path.splitext(os.path.basename(path))[0],
            scale * self.setting(path, "MODEL_SCALE", 1.0),
            self.setting(path, "CLIPS"),
            self.setting(path, "IDLE"),
            self.setting(path, "HIDDEN_PARTS", []))


def find(game, model, scripts=None):
    """Every distinct view that shows the .glb named `model` (without its extension) on the board,
    in the Godot project at `game`. Raises ValueError where a view can't be read."""
    scripts = scripts or Scripts(game)
    glb = re.escape(model) + r"\.glb"
    preload = re.compile(r'preload\("res://(?:[^"]*/)?' + glb + r'"\)')
    looks = os.path.join(game, "slices", "*", "look", "**", "*.gd")
    views = [
        scripts.view(path) for path in sorted(glob.glob(looks, recursive=True))
        if preload.search(scripts.text(path))]
    for scene in sorted(glob.glob(os.path.join(game, "**", "*.tscn"), recursive=True)):
        if not _skipped(game, scene):
            views += _instanced(game, scripts, scene, glb)
    distinct = {}
    for view in views:
        distinct.setdefault(view.key(), view)
    return list(distinct.values())


def _instanced(game, scripts, scene, glb):
    """The views of the nodes in `scene` that instance the .glb matched by `glb`: the script on each
    one's parent node, at the instance's own scale."""
    with open(scene, encoding="utf-8") as source:
        text = source.read()
    resources = {
        found.group("id"): found.group("path")
        for found in re.finditer(r'\[ext_resource [^\]]*path="(?P<path>[^"]+)"[^\]]*id="(?P<id>[^"]+)"', text)}
    models = {key for key, path in resources.items() if re.search("(^res://|/)" + glb + "$", path)}
    if not models:
        return []
    nodes = {}
    for found in re.finditer(r"^\[node ([^\]]*)\]\n((?:(?!\[).*\n?)*)", text, re.M):
        head, body = found.group(1), found.group(2)
        name = re.search(r'name="([^"]+)"', head).group(1)
        parent = re.search(r'parent="([^"]+)"', head)
        # The root is ".", its children their bare names, as scenes name their parents.
        path = "." if parent is None else (name if parent.group(1) == "." else parent.group(1) + "/" + name)
        nodes[path] = (head, body)
    views = []
    for path, (head, body) in nodes.items():
        instance = re.search(r'instance=ExtResource\("([^"]+)"\)', head)
        if instance is None or instance.group(1) not in models:
            continue
        parent = None if path == "." else nodes.get(path.rpartition("/")[0] if "/" in path else ".")
        script = re.search(r'^script = ExtResource\("([^"]+)"\)', parent[1], re.M) if parent else None
        if script is None:
            raise ValueError("%s: %s has no view script on its parent" % (_short(game, scene), path))
        res = resources[script.group(1)]
        views.append(scripts.view(os.path.join(game, res[len("res://"):]), _scale(body)))
    return views


def _scale(body):
    """The largest scale of a scene node's `transform`, 1 without one."""
    found = re.search(r"^transform = Transform3D\(([^)]*)\)", body, re.M)
    if found is None:
        return 1.0
    basis = [float(value) for value in found.group(1).split(",")[:9]]
    return max(math.sqrt(sum(basis[row * 3 + column] ** 2 for row in range(3))) for column in range(3))


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
