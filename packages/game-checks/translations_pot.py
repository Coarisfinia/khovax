"""Writes the translation template, translations/khovax.pot, from every text the player reads
(#1608): gettext, with the English text itself as the msgid, so a missing translation falls back
to it. With --check, it writes nothing and fails when the committed template is out of date.

The texts come from:
- scripts: the string literals passed to tr() and tr_n() (and atr(), atr_n()), with tr()'s
  literal context when it has one;
- scenes: the texts Godot translates by itself (text, placeholder_text, tooltip_text, title), but
  not on a node whose auto_translate_mode is disabled;
- content data: the fields its schema marks with "x-translate": true, followed through $ref,
  items, the combinators and if/then/else, so a new player-facing field is marked once, where it's
  declared;
- realms: the codex entry and gloss of each realms/<id>.md.

Texts are kept as written, text tags (${…}) included: a tag is resolved after the line is
translated. Each entry names the files it comes from, without line numbers, so moving a line
doesn't touch the template. The order is the files' order, then each file's, so related texts
stay together.

    uv run --locked --package khovax-game-checks packages/game-checks/translations_pot.py [--check]
"""

import json
import os
import re
import sys
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from game_shared import log
from game_shared.gdscript_code import Kind, tokens
from game_shared.git_files import git_files

TEMPLATE = Path("translations/khovax.pot")
HEADER = (
    'msgid ""\n'
    'msgstr ""\n'
    '"Project-Id-Version: khovax\\n"\n'
    '"MIME-Version: 1.0\\n"\n'
    '"Content-Type: text/plain; charset=UTF-8\\n"\n'
    '"Content-Transfer-Encoding: 8bit\\n"\n'
)
# The schema keyword that marks a player-facing text field.
MARK = "x-translate"
# A call whose first argument is the text: tr(text, context), tr_n(text, plural, n, context).
CALL = re.compile(r"(?<!\w)(a?tr(?:_n)?)\(\s*$")
COMMA = re.compile(r"\s*,\s*")
SCENE_TEXT = re.compile(
    r'^(?:[\w/]+/)?(?:text|placeholder_text|tooltip_text|title) = "((?:[^"\\]|\\.)*)"',
    re.MULTILINE | re.DOTALL,
)
SCENE_SECTION = re.compile(r"^\[", re.MULTILINE)
UNTRANSLATED = re.compile(r"^auto_translate_mode = 2$", re.MULTILINE)
REALM_CODEX = re.compile(r"^- (?:Entry|Gloss): (.+)$", re.MULTILINE)
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\"}


@dataclass
class Entry:
    context: str
    text: str
    plural: str | None
    files: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class Found:
    text: str
    context: str = ""
    plural: str | None = None


def unescaped(text: str) -> str:
    """A GDScript or scene string's text without its escapes."""
    out = []
    i = 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            char = text[i + 1]
            if char == "u" and re.fullmatch(r"[0-9a-fA-F]{4}", text[i + 2 : i + 6]):
                out.append(chr(int(text[i + 2 : i + 6], 16)))
                i += 6
                continue
            out.append(ESCAPES.get(char, "\\" + char))
            i += 2
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def literal(token: str) -> str:
    """A string token's text, without its quotes and escapes."""
    quote = token[:3] if token[:3] in ('"""', "'''") else token[0]
    return unescaped(token[len(quote) : -len(quote)])


def script_texts(source: str) -> Iterator[Found]:
    """The literal texts a script passes to tr() and its kin; a computed one (content read at run
    time) comes from elsewhere."""
    runs = [token for token in tokens(source) if token.kind != Kind.COMMENT]
    for i, token in enumerate(runs):
        match = CALL.search(token.text) if token.kind == Kind.CODE else None
        if match is None or i + 1 >= len(runs) or runs[i + 1].kind != Kind.STRING:
            continue
        strings = [literal(runs[i + 1].text)]
        # The string arguments right after it, each after a comma alone.
        at = i + 2
        while (
            at + 1 < len(runs)
            and runs[at].kind == Kind.CODE
            and COMMA.fullmatch(runs[at].text)
            and runs[at + 1].kind == Kind.STRING
        ):
            strings.append(literal(runs[at + 1].text))
            at += 2
        if match[1].endswith("_n"):
            if len(strings) >= 2:
                yield Found(strings[0], plural=strings[1])
        else:
            yield Found(strings[0], context=strings[1] if len(strings) > 1 else "")


def scene_texts(source: str) -> Iterator[Found]:
    """The texts a scene's nodes show, which Godot translates unless a node turns that off."""
    for section in SCENE_SECTION.split(source):
        if UNTRANSLATED.search(section):
            continue
        for match in SCENE_TEXT.finditer(section):
            yield Found(unescaped(match[1]))


def realm_texts(source: str) -> Iterator[Found]:
    """A realm's codex entry and gloss."""
    _, _, codex = source.partition("\n## Codex\n")
    codex = codex.split("\n## ", 1)[0]
    for match in REALM_CODEX.finditer(codex):
        yield Found(match[1].strip())


def stripped_jsonc(text: str) -> str:
    """JSON with comments without its comments, as the game's Jsonc.strip reads it."""
    out = []
    i = 0
    in_string = False
    while i < len(text):
        char = text[i]
        if in_string:
            out.append(text[i : i + 2] if char == "\\" else char)
            i += 2 if char == "\\" else 1
            in_string = char != '"'
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end < 0 else end
        elif text.startswith("/*", i) and (end := text.find("*/", i + 2)) >= 0:
            out.append("\n" * text.count("\n", i, end))
            i = end + 2
        else:
            in_string = char == '"'
            out.append(char)
            i += 1
    return "".join(out)


def marked_paths(schema: dict[str, Any]) -> set[tuple[str, ...]]:
    """The paths into a file (property names, and "*" for an array's items) of every field the
    schema marks as player-facing text."""
    found: set[tuple[str, ...]] = set()

    def resolve(reference: str) -> Any:
        node: Any = schema
        for part in reference.removeprefix("#").split("/")[1:]:
            node = node[part]
        return node

    def walk(node: Any, path: tuple[str, ...], seen: frozenset[str]) -> None:
        if not isinstance(node, dict):
            return
        if node.get(MARK) is True:
            found.add(path)
        reference = node.get("$ref")
        if isinstance(reference, str) and reference.startswith("#") and reference not in seen:
            walk(resolve(reference), path, seen | {reference})
        for name, child in node.get("properties", {}).items():
            walk(child, (*path, name), seen)
        walk(node.get("items"), (*path, "*"), seen)
        for combined in ("allOf", "anyOf", "oneOf"):
            for child in node.get(combined, []):
                walk(child, path, seen)
        for branch in ("if", "then", "else"):
            walk(node.get(branch), path, seen)

    walk(schema, (), frozenset())
    return found


def values_at(data: Any, path: tuple[str, ...]) -> Iterator[Any]:
    """Every value in the data at the path, an array's items in their order for each "*"."""
    if not path:
        yield data
    elif path[0] == "*" and isinstance(data, list):
        for item in data:
            yield from values_at(item, path[1:])
    elif isinstance(data, dict) and path[0] in data:
        yield from values_at(data[path[0]], path[1:])


def content_texts(source: str, paths: set[tuple[str, ...]]) -> Iterator[Found]:
    """A content file's player-facing texts, in the order of the schema's marked paths."""
    data = json.loads(stripped_jsonc(source))
    for path in sorted(paths):
        for value in values_at(data, path):
            if isinstance(value, str):
                yield Found(value)


def schema_of(data_file: str) -> str:
    """The schema a content file is checked against (as content_schemas_check.py pairs them)."""
    parts = Path(data_file).parts
    if parts[0] == "core":
        return f"core/data/schemas/{parts[2]}.schema.json"
    # slices/<slice>/data/<file> belongs to the slice's own kind, named for the slice.
    kind = parts[1] if len(parts) == 4 else parts[3]
    return f"slices/{parts[1]}/data/{kind}.schema.json"


def found_in(path: str, marked: dict[str, set[tuple[str, ...]]]) -> Iterator[Found]:
    source = Path(path).read_text(encoding="utf-8")
    if path.endswith(".gd"):
        yield from script_texts(source)
    elif path.endswith(".tscn"):
        yield from scene_texts(source)
    elif path.endswith(".md"):
        yield from realm_texts(source)
    else:
        schema = schema_of(path)
        if schema not in marked:
            marked[schema] = marked_paths(json.loads(Path(schema).read_text(encoding="utf-8")))
        yield from content_texts(source, marked[schema])


def entries() -> list[Entry]:
    """Every translatable text, each once with every file it's in."""
    files = git_files("*.gd", "*.tscn", "core/data/*.jsonc", "slices/*/data/*.jsonc", "realms/*.md")
    # The tools and tests are never shown to a player.
    files = [path for path in files if not path.startswith(("tools/", "tests/"))]
    marked: dict[str, set[tuple[str, ...]]] = {}
    by_key: dict[tuple[str, str], Entry] = {}
    for path in sorted(files):
        for found in found_in(path, marked):
            if not found.text:
                continue
            key = (found.context, found.text)
            entry = by_key.setdefault(key, Entry(found.context, found.text, found.plural))
            if entry.plural is None:
                entry.plural = found.plural
            if path not in entry.files:
                entry.files.append(path)
    return list(by_key.values())


def quoted(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + escaped.replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r") + '"'


def template(found: list[Entry]) -> str:
    blocks = [HEADER]
    for entry in found:
        lines = [f"#: {path}" for path in entry.files]
        if entry.context:
            lines.append(f"msgctxt {quoted(entry.context)}")
        lines.append(f"msgid {quoted(entry.text)}")
        if entry.plural is None:
            lines.append('msgstr ""')
        else:
            lines += [f"msgid_plural {quoted(entry.plural)}", 'msgstr[0] ""', 'msgstr[1] ""']
        blocks.append("\n".join(lines) + "\n")
    return "\n".join(blocks)


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    text = template(entries())
    if "--check" not in sys.argv[1:]:
        TEMPLATE.parent.mkdir(exist_ok=True)
        TEMPLATE.write_text(text, encoding="utf-8", newline="\n")
        return 0
    if not TEMPLATE.is_file() or TEMPLATE.read_text(encoding="utf-8") != text:
        log.error(
            "out of date: run `uv run --locked --package khovax-game-checks"
            " packages/game-checks/translations_pot.py` and commit the result",
            TEMPLATE.as_posix(),
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
