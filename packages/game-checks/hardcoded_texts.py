"""Fails on a text the player reads that doesn't go through tr() with a literal string (#1693), so
translations_pot.py can't miss it (#1608).

A text is player-facing when it flows into what a Control shows:
- assigned to text, tooltip_text, placeholder_text or title (also +=);
- passed to Godot's text methods (set_text, add_item, add_tab, set_tab_title, append_text, …);
- passed to a game function whose parameter flows into one of these (MenuWidgets.label's text,
  NoticeScreen.notify's title), returned by a function whose result does, or put into a local or
  a member (a line, an Array[String] of lines) that does. The flow is followed to a fixed point,
  through the presentation's scripts only (game/, ui/, look/): the rules, meta and core hand it
  data, and their strings are ids and error messages. A call names its function by its class,
  by self or bare in its own script where it can, and only by name elsewhere; a shown parameter's
  default and a shown member's initializer count too, and a helper outside the presentation
  (TextTags.shown) passes on the parameters and locals handed to it, never its ids.
In such an expression, a hit is a string literal outside tr() (formatted with % or as a value
handed to String.format(), glued with +, in an array of lines), a constant the expression names,
even inside tr() (the extractor reads only literals), through the constants it aliases: its
string, its array's strings or its dictionary's string keys, and a name made from an id with
capitalize(). A constant dictionary handed to format(), straight or through a local, member or
parameter, counts by its values. Not a hit: a literal without a letter outside its format
specifiers, BBCode and text tags (empty, numbers, symbols, "%s: %d"), a StringName or NodePath
(&"…", ^"…"), the condition of an `x if c else y`, a dictionary's key (a format's placeholder) and
a literal inside another call (a key, an id).
In scenes: a text on a node whose auto_translate_mode is disabled, and a TabContainer's child,
whose node name is its tab's title. A script that adds tabs to a TabContainer titles them with
set_tab_title, since TabContainer titles a tab by its node's name, which no extractor sees.
The tools and tests are never shown to a player; debug and log output never flows into a Control.

The hits that exist today wait in KNOWN, each with the issue that moves it over, and a listed hit
that is gone fails until it's taken off the list, so the list only shrinks. A deliberate exception
goes into ALLOWED with its reason. Hits are named by file and text, never by line, so moving a
line changes nothing.

    uv run --locked --package khovax-game-checks packages/game-checks/hardcoded_texts.py [--list]

--list also prints every hit, listed or not, with its line.
"""

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
from hardcoded_texts_known import ALLOWED, KNOWN
from translations_pot import SCENE_MODE, SCENE_NODE, SCENE_SECTION, SCENE_TEXT, literal, unescaped

LISTS = "packages/game-checks/hardcoded_texts_known.py"
TEXT_PROPERTIES = {"text", "tooltip_text", "placeholder_text", "title"}
# Godot's methods that show their string arguments.
GODOT_TEXT_CALLS = {
    "set_text", "set_tooltip_text", "set_placeholder", "set_title", "add_item", "add_icon_item",
    "add_check_item", "add_icon_check_item", "add_radio_check_item", "add_submenu_item",
    "set_item_text", "set_item_tooltip", "add_tab", "set_tab_title", "set_tab_tooltip",
    "append_text", "add_text", "parse_bbcode",
}  # fmt: skip
TRANSLATE_CALLS = {"tr", "tr_n", "atr", "atr_n"}
# Methods that put a value into a local array of lines.
APPENDS = {"append", "push_back", "push_front", "insert", "append_array"}
# The name made from an id; a hit's text when one flows into a Control.
FROM_ID = "capitalize()"
LETTER = re.compile(r"[^\W\d_]")
# What a text holds besides words: format specifiers, BBCode tags and text tags (${…}).
MARKUP = re.compile(
    r"%[-+ 0#]*[0-9*]*(?:\.[0-9*]+)?[a-zA-Z%]|\[/?[a-z_]+(?:=[^\]]*)?\]|\$\{[^}]*\}"
)
# Calls whose arguments make up their result's text.
PASS_THROUGH = {"join", "str"}
LEXEME = re.compile(
    r"\s+|[A-Za-z_]\w*|\d[\w.]*|:=|\+=|-=|\*=|/=|%=|==|!=|<=|>=|->|\*\*|&&|\|\||\\\n|."
)
OPEN, CLOSE = "([{", ")]}"
ASSIGN = {"=", ":=", "+="}
DISABLED = 2
# Keywords that come before a value: a ( or [ after one opens the value, not a call or index.
KEYWORDS = {
    "if", "elif", "else", "and", "or", "not", "in", "is", "await", "return", "while", "match", "func",
}  # fmt: skip
# The statements whose header ends in a colon, with their body after it or on the next lines.
BLOCKS = {"if", "elif", "else", "for", "while", "func"}
PRESENTATION = re.compile(r"(^|/)(game|ui|look)/")


@dataclass(frozen=True)
class Tok:
    kind: str  # "str", "id", "op" or "num"
    text: str
    line: int
    prefix: str = ""  # a string's & (StringName) or ^ (NodePath)


@dataclass
class Statement:
    indent: int
    toks: list[Tok]


@dataclass
class Func:
    name: str
    params: list[str]
    body: list[Statement]
    names: set[str] = field(default_factory=set)  # its parameters and locals
    defaults: dict[int, list[Tok]] = field(default_factory=dict)  # by parameter


# The context of a member's initializer, which has no parameters or locals.
NO_FUNC = Func("", [], [])


@dataclass(frozen=True)
class Hit:
    file: str
    text: str
    line: int


@dataclass
class Script:
    path: str
    # Each constant's texts: a string's, an array's strings, a dictionary's string keys.
    consts: dict[str, list[tuple[str, int]]] = field(default_factory=dict)
    # Each constant dictionary's values that are a string or another constant's name, shown when
    # it fills in a format() (#1715). Only dictionaries: an array's items are its texts already.
    const_values: dict[str, list[Tok]] = field(default_factory=dict)
    # Each constant that names another (`const TITLE = NAME`, `const TITLE = Other.NAME`, #1734).
    aliases: dict[str, list[Tok]] = field(default_factory=dict)
    # Each member variable's initializer (empty without one).
    members: dict[str, list[Tok]] = field(default_factory=dict)
    funcs: list[Func] = field(default_factory=list)


def is_words(text: str) -> bool:
    """Whether the text holds a letter outside its markup."""
    return LETTER.search(MARKUP.sub("", text)) is not None


def statements(source: str) -> Iterator[Statement]:
    """The script's logical lines: a line continues while a bracket is open or after a \\."""
    current: list[Tok] = []
    indent = 0
    depth = 0
    line = 1
    for run in tokens(source):
        if run.kind == Kind.COMMENT:
            continue
        if run.kind == Kind.STRING:
            code_before = current[-1] if current else None
            prefix = ""
            if code_before and code_before.kind == "op" and code_before.text in "&^":
                prefix = current.pop().text
            elif code_before and code_before.kind == "id" and code_before.text == "r":
                current.pop()
                if current and current[-1].kind == "op" and current[-1].text in "&^":
                    prefix = current.pop().text
            raw = code_before is not None and code_before.text == "r"
            current.append(Tok("str", literal(run.text, "r" if raw else ""), line, prefix))
            line += run.text.count("\n")
            continue
        for match in LEXEME.finditer(run.text):
            lexeme = match[0]
            if lexeme.isspace() or lexeme == "\\\n":
                newlines = lexeme.count("\n")
                if "\n" in lexeme and lexeme != "\\\n" and depth == 0:
                    if current:
                        yield Statement(indent, current)
                    current = []
                    indent = len(lexeme.rsplit("\n", 1)[1])
                line += newlines
                continue
            if lexeme in OPEN:
                depth += 1
            elif lexeme in CLOSE:
                depth = max(depth - 1, 0)
            kind = "id" if lexeme[0].isalpha() or lexeme[0] == "_" else "num"
            kind = kind if lexeme[0].isalnum() or lexeme[0] == "_" else "op"
            current.append(Tok(kind, lexeme, line))
    if current:
        yield Statement(indent, current)


def matching(toks: list[Tok], at: int) -> int:
    """The index of the bracket closing the one opening at `at` (or the end)."""
    depth = 0
    for i in range(at, len(toks)):
        if toks[i].text in OPEN and toks[i].kind == "op":
            depth += 1
        elif toks[i].text in CLOSE and toks[i].kind == "op":
            depth -= 1
            if depth == 0:
                return i
    return len(toks)


def split_args(toks: list[Tok], open_at: int) -> list[list[Tok]]:
    """A call's arguments, its brackets opening at `open_at`."""
    args: list[list[Tok]] = [[]]
    depth = 0
    for tok in toks[open_at + 1 : matching(toks, open_at)]:
        if tok.kind == "op" and tok.text in OPEN:
            depth += 1
        elif tok.kind == "op" and tok.text in CLOSE:
            depth -= 1
        if tok.kind == "op" and tok.text == "," and depth == 0:
            args.append([])
        else:
            args[-1].append(tok)
    return [arg for arg in args if arg]


def is_call(toks: list[Tok], i: int) -> bool:
    """Whether the ( at `i` opens a call (it follows a name, not a keyword)."""
    before = toks[i - 1] if i > 0 else None
    return (
        toks[i].text == "(" and before is not None and before.kind == "id"
        and not is_keyword(toks, i - 1)
    )  # fmt: skip


def is_keyword(toks: list[Tok], at: int) -> bool:
    """Whether the name at `at` is a keyword, not a method of the same name (String.match())."""
    return toks[at].text in KEYWORDS and not (at > 0 and toks[at - 1].text == ".")


def simple_statements(toks: list[Tok]) -> Iterator[list[Tok]]:
    """A line's simple statements: its parts between semicolons at the outer level, and of each
    block header with an inline body (`if c: for w in x: shown = w`), the header up to its colon
    and then the body's own."""
    depth = 0
    start = 0
    for i, tok in enumerate([*toks, Tok("op", ";", 0)]):
        if tok.kind == "op" and tok.text in OPEN:
            depth += 1
        elif tok.kind == "op" and tok.text in CLOSE:
            depth -= 1
        elif depth == 0 and tok.kind == "op" and tok.text == ";":
            part = toks[start:i]
            start = i + 1
            colon = header_colon(part)
            if colon is not None and colon + 1 < len(part):
                yield part[: colon + 1]
                yield from simple_statements(part[colon + 1 :])
            elif part:
                yield part


def header_colon(toks: list[Tok]) -> int | None:
    """Where the header of a block statement (if, elif, else, for, while, func) ends: its colon
    at the outer level, after a for's `in` (its loop variable may be typed) and after a func's
    parameters. None for a statement that opens no block."""
    words = [tok.text for tok in toks]
    if words[:1] == ["static"]:
        words = words[1:]
    if not words or words[0] not in BLOCKS:
        return None
    start = words.index("in") if words[0] == "for" and "in" in words else 0
    if words[0] == "func":
        opened = next((i for i, tok in enumerate(toks) if tok.text == "("), len(toks))
        start = matching(toks, opened) + 1
    depth = 0
    for i in range(start, len(toks)):
        if toks[i].kind == "op" and toks[i].text in OPEN:
            depth += 1
        elif toks[i].kind == "op" and toks[i].text in CLOSE:
            depth -= 1
        elif depth == 0 and toks[i].kind == "op" and toks[i].text == ":":
            return i
    return None


def const_texts(toks: list[Tok]) -> list[tuple[str, int]]:
    """The texts a constant holds: its string, or its array's strings or its dictionary's string
    keys, one level deep (a StringName or NodePath is an id)."""
    assign = next((i for i, tok in enumerate(toks) if tok.text in ("=", ":=")), len(toks))
    value = toks[assign + 1 :]
    if len(value) == 1 and value[0].kind == "str" and not value[0].prefix:
        return [(value[0].text, value[0].line)]
    if not value or value[0].text not in "[{" or value[0].kind != "op":
        return []
    found = []
    depth = 0
    for i, tok in enumerate(value):
        if tok.kind == "op" and tok.text in OPEN:
            depth += 1
        elif tok.kind == "op" and tok.text in CLOSE:
            depth -= 1
        elif tok.kind == "str" and depth == 1 and not tok.prefix:
            after = value[i + 1].text if i + 1 < len(value) else ""
            if value[0].text == "[" or after == ":":
                found.append((tok.text, tok.line))
    return found


def const_values(toks: list[Tok]) -> list[Tok] | None:
    """A constant dictionary's values that are a string or a name (a StringName or NodePath is
    an id), one level deep; None for a constant that isn't a dictionary."""
    assign = next((i for i, tok in enumerate(toks) if tok.text in ("=", ":=")), len(toks))
    value = toks[assign + 1 :]
    if not value or value[0].text != "{" or value[0].kind != "op":
        return None
    found = []
    for entry in split_args(value, 0):
        colon = next((i for i, tok in enumerate(entry) if tok.text in (":", "=")), None)
        rest = entry[colon + 1 :] if colon is not None else []
        plain = len(rest) == 1 and not rest[0].prefix
        if plain and rest[0].kind in ("id", "str"):
            found.append(rest[0])
    return found


def const_alias(toks: list[Tok]) -> list[Tok]:
    """The constant a constant names (`NAME` or `Other.NAME`), or nothing."""
    assign = next((i for i, tok in enumerate(toks) if tok.text in ("=", ":=")), len(toks))
    value = toks[assign + 1 :]
    if len(value) == 1 and value[0].kind == "id":
        return value
    if len(value) == 3 and value[1].text == "." and value[0].kind == value[2].kind == "id":
        return value
    return []


def without_annotations(toks: list[Tok]) -> list[Tok]:
    """A statement without its leading annotations (@export, @export_range(…), @onready)."""
    at = 0
    while at + 1 < len(toks) and toks[at].text == "@" and toks[at + 1].kind == "id":
        at += 2
        if at < len(toks) and toks[at].text == "(":
            at = matching(toks, at) + 1
    return toks[at:]


def parse(path: str) -> Script:
    script = Script(path)
    lines = list(statements(Path(path).read_text(encoding="utf-8")))
    i = 0
    while i < len(lines):
        statement = lines[i]
        words = [tok.text for tok in statement.toks]
        start = 1 if words[:2] == ["static", "func"] else 0
        if words[start : start + 1] == ["func"] and len(words) > start + 1:
            open_at = start + 2
            args = split_args(statement.toks, open_at)
            params = [arg[0].text for arg in args]
            body = []
            colon = header_colon(statement.toks)
            if colon is not None and colon + 1 < len(statement.toks):
                # A one-line function: its body follows the colon.
                body.append(Statement(statement.indent + 1, statement.toks[colon + 1 :]))
            i += 1
            while i < len(lines) and lines[i].indent > statement.indent:
                body.append(lines[i])
                i += 1
            func = Func(words[start + 1], params, body, set(params))
            for index, arg in enumerate(args):
                assign = next((i for i, tok in enumerate(arg) if tok.text in ("=", ":=")), None)
                if assign is not None:
                    func.defaults[index] = arg[assign + 1 :]
            for inner in body:
                for part in simple_statements(inner.toks):
                    if part[0].text in ("var", "for") and len(part) > 1:
                        func.names.add(part[1].text)
            script.funcs.append(func)
            continue
        toks = without_annotations(statement.toks)
        member = [tok.text for tok in toks]
        member = member[1:] if member[:1] == ["static"] else member
        if member[:1] == ["var"] and len(member) > 1:
            assign = next((i for i, tok in enumerate(toks) if tok.text in ("=", ":=")), len(toks))
            script.members[member[1]] = toks[assign + 1 :]
        if member[:1] == ["const"] and len(member) > 1:
            script.consts[member[1]] = const_texts(toks)
            values = const_values(toks)
            if values is not None:
                script.const_values[member[1]] = values
            alias = const_alias(toks)
            if alias:
                script.aliases[member[1]] = alias
        i += 1
    return script


class Flow:
    """What the scripts' texts flow into, followed to a fixed point."""

    def __init__(self, scripts: list[Script]) -> None:
        self.scripts = scripts
        self.by_class: dict[str, Script] = {}
        for script in scripts:
            text = Path(script.path).read_text(encoding="utf-8")
            match = re.search(r"^class_name (\w+)", text, re.MULTILINE)
            if match:
                self.by_class[match[1]] = script
        # Only the presentation shows texts; the rules, meta and core hand it data and errors.
        self.shown = [script for script in scripts if PRESENTATION.search(script.path)]
        self.owners: dict[int, Script] = {
            id(func): script for script in self.shown for func in script.funcs
        }
        self.by_name: dict[str, list[Func]] = {}
        for script in self.shown:
            for func in script.funcs:
                self.by_name.setdefault(func.name, []).append(func)
        # Keyed by the function's id(): two scripts' functions of one name are told apart.
        self.text_params: dict[int, set[int]] = {}
        self.text_funcs: set[int] = set()
        self.text_locals: dict[int, set[str]] = {}
        self.text_members: dict[str, set[str]] = {}
        # Locals and members that hold a format()'s values (#1734): a constant dictionary
        # assigned to one counts by its values, not its keys.
        self.format_locals: dict[int, set[str]] = {}
        self.format_members: dict[str, set[str]] = {}
        # Parameters that hold a format()'s values (#1741), by index: a call's argument for one
        # (and its default) is read the same way.
        self.format_params: dict[int, set[int]] = {}
        self.hits: set[Hit] = set()
        self.changed = False

    def run(self) -> set[Hit]:
        self.changed = True
        while self.changed:
            self.changed = False
            for script in self.shown:
                for func in script.funcs:
                    for statement in func.body:
                        self.statement(script, func, statement.toks)
                    # A shown parameter's default is shown when a call leaves it out.
                    for index in sorted(self.text_params.get(id(func), set())):
                        self.expression(script, func, func.defaults.get(index, []))
                    format_params = self.format_params.get(id(func), set())
                    for index in sorted(format_params & func.defaults.keys()):
                        self.format_values(script, func, func.defaults[index])
                for member in sorted(self.text_members.get(script.path, set())):
                    self.expression(script, NO_FUNC, script.members[member])
                for member in sorted(self.format_members.get(script.path, set())):
                    self.format_values(script, NO_FUNC, script.members[member])
        return self.hits

    def outside(self, toks: list[Tok], at: int) -> bool:
        """Whether the call opening at `at` names a class outside the presentation (a helper such
        as TextTags.shown), whose arguments make up its result."""
        if at < 3 or toks[at - 2].text != ".":
            return False
        owner = self.by_class.get(toks[at - 3].text)
        return owner is not None and owner not in self.shown

    def resolve(self, script: Script, toks: list[Tok], at: int) -> list[Func]:
        """The presentation's functions the call opening at `at` may reach: a class's own when it
        names the class (or self), the script's own when it's bare, else every one of that name."""
        name = toks[at - 1].text
        if at >= 3 and toks[at - 2].text == ".":
            receiver = toks[at - 3].text
            owner = script if receiver == "self" else self.by_class.get(receiver)
            if owner is not None:
                return [func for func in owner.funcs if func.name == name]
            return self.by_name.get(name, [])
        own = [func for func in script.funcs if func.name == name]
        return own or self.by_name.get(name, [])

    def mark(
        self, found: set[str] | set[int] | dict[int, set[int]], key: Any, value: int | None = None
    ) -> None:
        if isinstance(found, set):
            if key not in found:
                found.add(key)
                self.changed = True
        elif value is not None and value not in found.setdefault(key, set()):
            found[key].add(value)
            self.changed = True

    def locals_of(self, func: Func) -> set[str]:
        return self.text_locals.setdefault(id(func), set())

    def statement(self, script: Script, func: Func, toks: list[Tok]) -> None:
        parts = list(simple_statements(toks))
        if parts != [toks]:
            # Statements after a semicolon or in an inline body (`if c: shown = "x"`) each count
            # on their own.
            for part in parts:
                self.statement(script, func, part)
            return
        colon = header_colon(toks)
        words = [tok.text for tok in toks]
        text_locals = self.locals_of(func)
        # A member that is shown carries what's assigned to it anywhere in its script.
        members = self.text_members.get(script.path, set()) - func.names
        format_locals = self.format_locals.setdefault(id(func), set())
        format_carriers = format_locals | (
            self.format_members.get(script.path, set()) - func.names
        )
        carriers = text_locals | members | format_carriers
        if words[:1] == ["return"] and id(func) in self.text_funcs:
            self.expression(script, func, toks[1:])
        if words[:1] == ["for"] and len(words) > 3 and words[1] in text_locals:
            in_at = words.index("in") if "in" in words else len(words)
            self.expression(script, func, toks[in_at + 1 : colon])
        assign = next(
            (
                i
                for i, tok in enumerate(toks)
                if tok.kind == "op" and tok.text in ASSIGN and self.depth(toks, i) == 0
            ),
            None,
        )
        if assign is not None:
            self_target = words[:2] == ["self", "."]
            target = toks[2:assign] if self_target else toks[:assign]
            value = toks[assign + 1 :]
            # `self.values = …` names the member even where a local shadows it.
            own_members = self.text_members.get(script.path, set())
            format_targets = format_carriers
            text_targets = text_locals | members
            if self_target:
                format_targets = self.format_members.get(script.path, set())
                text_targets = own_members
            # A keyed or attribute write names its carrier the same way (#1741).
            targets = text_targets | format_targets
            if words[0] == "var" and len(words) > 1:
                if words[1] in text_locals:
                    self.expression(script, func, value)
                if words[1] in format_locals:
                    self.format_values(script, func, value)
            elif len(target) == 1 and target[0].text in format_targets:
                self.format_values(script, func, value)
                if target[0].text in text_targets:
                    self.expression(script, func, value)
            elif target[0].text in targets and (
                len(target) == 1
                or target[1].text == "["
                or (len(target) == 3 and target[1].text == ".")
            ):
                # The carrier itself, or one of its keys (`values["name"] = …`, `values.name = …`).
                self.expression(script, func, value)
            elif target[-1].text in TEXT_PROPERTIES and (
                len(target) > 1
                and target[-2].text == "."
                or len(target) == 1
                and target[0].text not in func.names | script.members.keys()
            ):
                self.expression(script, func, value)
        for i in range(len(toks)):
            if not is_call(toks, i):
                continue
            name = toks[i - 1].text
            args = split_args(toks, i)
            owner = toks[i - 3].text if i >= 3 and toks[i - 2].text == "." else None
            if name in GODOT_TEXT_CALLS:
                for arg in args:
                    self.expression(script, func, arg)
            elif name in APPENDS and owner in carriers:
                for arg in args[-1:]:
                    self.expression(script, func, arg)
            else:
                for reached in self.resolve(script, toks, i):
                    for index in sorted(self.text_params.get(id(reached), set())):
                        if index < len(args):
                            self.expression(script, func, args[index])
                    for index in sorted(self.format_params.get(id(reached), set())):
                        if index < len(args):
                            self.format_values(script, func, args[index])

    @staticmethod
    def depth(toks: list[Tok], at: int) -> int:
        depth = 0
        for tok in toks[:at]:
            if tok.kind == "op" and tok.text in OPEN:
                depth += 1
            elif tok.kind == "op" and tok.text in CLOSE:
                depth -= 1
        return depth

    def expression(
        self, script: Script, func: Func, toks: list[Tok], carry_only: bool = False
    ) -> None:
        """An expression whose value a Control shows; with `carry_only`, only the parameters,
        locals and members it names are followed."""
        i = 0
        while i < len(toks):
            tok = toks[i]
            if tok.kind == "id" and tok.text == "if":
                # The condition of `x if c else y` is never shown.
                i = self.skip_condition(toks, i)
                continue
            if tok.kind == "op" and tok.text == "(" and is_call(toks, i):
                self.call(script, func, toks, i)
                if toks[i - 1].text in PASS_THROUGH:
                    for arg in split_args(toks, i):
                        self.expression(script, func, arg, carry_only)
                elif self.is_format(script, toks, i):
                    # Only its values; a second argument is the placeholder's pattern.
                    for arg in split_args(toks, i)[:1]:
                        self.format_values(script, func, arg, carry_only)
                elif self.outside(toks, i):
                    # Its literals and constants are ids (a tag's kind), but a parameter or
                    # local handed to it is still shown.
                    for arg in split_args(toks, i):
                        self.expression(script, func, arg, carry_only=True)
                i = matching(toks, i) + 1
                continue
            if tok.kind == "op" and tok.text == "{":
                # A dictionary's keys are ids (a format's placeholders), but its values are shown
                # when String.format() fills them in (#1715), or when one is looked up.
                for value in self.dict_values(toks, i):
                    self.expression(script, func, value, carry_only)
                i = matching(toks, i) + 1
                continue
            if tok.kind == "op" and tok.text == "[" and self.subscript(toks, i):
                i = matching(toks, i) + 1
                continue
            if carry_only and tok.kind != "id":
                pass
            elif tok.kind == "str" and not tok.prefix and is_words(tok.text):
                self.hits.add(Hit(script.path, tok.text, tok.line))
            elif tok.kind == "id" and not self.attribute_or_call(toks, i):
                self.name(script, func, toks, i, carry_only)
            i += 1

    @staticmethod
    def attribute_or_call(toks: list[Tok], at: int) -> bool:
        """Whether the name at `at` is called, or only an attribute of it is read (a method of a
        text, such as substr(), keeps it a text)."""
        after = [tok.text for tok in toks[at + 1 : at + 4]]
        return after[:1] == ["("] or after[:1] == ["."] and after[2:3] != ["("]

    @staticmethod
    def skip_condition(toks: list[Tok], at: int) -> int:
        depth = 0
        for i in range(at + 1, len(toks)):
            if toks[i].kind == "op" and toks[i].text in OPEN:
                depth += 1
            elif toks[i].kind == "op" and toks[i].text in CLOSE:
                depth -= 1
            elif depth == 0 and toks[i].text == "else":
                return i + 1
        return len(toks)

    def is_format(self, script: Script, toks: list[Tok], at: int) -> bool:
        """Whether the call opening at `at` is a text's format(), not a game function of that
        name: its values make up its result (a dictionary's values or an array's items, #1715).
        A receiver that names no class of the game (a text, tr()'s result) is a text."""
        if toks[at - 1].text != "format" or at < 2 or toks[at - 2].text != ".":
            return False
        receiver = toks[at - 3].text if at >= 3 else ""
        owner = script if receiver == "self" else self.by_class.get(receiver)
        return owner is None or not any(func.name == "format" for func in owner.funcs)

    def format_values(
        self, script: Script, func: Func, arg: list[Tok], carry_only: bool = False
    ) -> None:
        """The values a format() fills in: a constant dictionary's values (#1715), or a local or
        member holding them, whose assignments are followed the same way (#1734), or a parameter
        holding them, whose calls' arguments are (#1741)."""
        while len(arg) > 2 and arg[0].text == "(" and matching(arg, 0) == len(arg) - 1:
            arg = arg[1:-1]  # `(VALUES)` is VALUES
        word = arg[0].text if len(arg) == 1 and arg[0].kind == "id" else ""
        if [tok.text for tok in arg[:2]] == ["self", "."] and len(arg) == 3:
            word = arg[2].text if arg[2].text in script.members else ""
        elif word in func.params:
            self.mark(self.format_params, id(func), func.params.index(word))
            return
        elif word in func.names:
            self.mark(self.format_locals.setdefault(id(func), set()), word)
            return
        if word in script.members and (len(arg) == 3 or word not in func.names):
            self.mark(self.format_members.setdefault(script.path, set()), word)
        elif carry_only or not self.format_const(script, func, arg):
            self.expression(script, func, arg, carry_only)

    def format_const(self, script: Script, func: Func, arg: list[Tok]) -> bool:
        """Whether a format()'s values are a constant dictionary, whose values are then hits and
        whose keys are its placeholders (#1715)."""
        if len(arg) == 1 and arg[0].kind == "id" and arg[0].text not in func.names:
            owner: Script | None = script
        elif len(arg) == 3 and arg[1].text == "." and arg[0].kind == arg[2].kind == "id":
            owner = self.by_class.get(arg[0].text)
        else:
            return False
        if owner is None or arg[-1].text in owner.members:
            return False
        owner, word = self.unalias(owner, arg[-1].text)
        if word not in owner.const_values:
            return False
        for value in owner.const_values[word]:
            if value.kind == "id":
                # Another constant of its script (`{"name": TITLE}`).
                self.const(owner, value.text)
            elif is_words(value.text):
                self.hits.add(Hit(owner.path, value.text, value.line))
        return True

    @staticmethod
    def dict_values(toks: list[Tok], at: int) -> Iterator[list[Tok]]:
        """The values of the dictionary opening at `at`: each entry after its key's : (or =)."""
        for entry in split_args(toks, at):
            colon = next(
                (
                    i
                    for i, tok in enumerate(entry)
                    if tok.kind == "op" and tok.text in (":", "=") and Flow.depth(entry, i) == 0
                ),
                None,
            )
            if colon is not None:
                yield entry[colon + 1 :]

    @staticmethod
    def subscript(toks: list[Tok], at: int) -> bool:
        """A [ after a value indexes it (a key)."""
        before = toks[at - 1] if at > 0 else None
        if before is None or before.kind == "id" and is_keyword(toks, at - 1):
            return False
        return before.kind in ("id", "str") or before.text in ")]"

    def call(self, script: Script, func: Func, toks: list[Tok], at: int) -> None:
        name = toks[at - 1].text
        if name in TRANSLATE_CALLS:
            # The extractor reads only literals: a constant inside tr() is missed.
            for arg in split_args(toks, at)[:1]:
                if len(arg) in (1, 3) and arg[-1].kind == "id":
                    self.name(script, func, arg, len(arg) - 1)
        elif name == "capitalize":
            self.hits.add(Hit(script.path, FROM_ID, toks[at].line))
        else:
            for reached in self.resolve(script, toks, at):
                self.mark(self.text_funcs, id(reached))

    def name(
        self, script: Script, func: Func, toks: list[Tok], at: int, carry_only: bool = False
    ) -> None:
        """A name in a shown expression: a constant's text is a hit, and a parameter or local
        carries the text further."""
        word = toks[at].text
        if at >= 2 and toks[at - 1].text == ".":
            owner = self.by_class.get(toks[at - 2].text)
            if owner is not None and not carry_only:
                self.const(owner, word)
            return
        if word in func.params:
            self.mark(self.text_params, id(func), func.params.index(word))
        elif word in func.names:
            self.mark(self.locals_of(func), word)
        elif word in script.members:
            self.mark(self.text_members.setdefault(script.path, set()), word)
        elif not carry_only:
            self.const(script, word)

    def unalias(self, script: Script, word: str) -> tuple[Script, str]:
        """The constant an alias chain ends at (`const TITLE = NAME`, #1734)."""
        seen: set[tuple[str, str]] = set()
        while word in script.aliases and (script.path, word) not in seen:
            seen.add((script.path, word))
            alias = script.aliases[word]
            owner = script if len(alias) == 1 else self.by_class.get(alias[0].text)
            if owner is None:
                break
            script, word = owner, alias[-1].text
        return script, word

    def const(self, script: Script, word: str) -> None:
        script, word = self.unalias(script, word)
        for text, line in script.consts.get(word, []):
            if is_words(text):
                self.hits.add(Hit(script.path, text, line))


def tab_title_hits(script: Script) -> Iterator[Hit]:
    """A script that adds children to a TabContainer and never sets their titles."""
    source = Path(script.path).read_text(encoding="utf-8")
    tabs = re.findall(r"var (\w+): TabContainer\b", source)
    for name in tabs:
        added = re.search(rf"\b{name}\.add_child\(", source)
        if added and not re.search(rf"\b{name}\.set_tab_title\(", source):
            line = source.count("\n", 0, added.start()) + 1
            yield Hit(script.path, "tab titles from node names", line)


def scene_hits(path: str) -> Iterator[Hit]:
    """A scene's texts that Godot doesn't translate, and the names of a TabContainer's
    children."""
    source = Path(path).read_text(encoding="utf-8")
    disabled: dict[str, bool] = {}
    tab_containers: set[str] = set()
    line = 1
    for section in SCENE_SECTION.split(source):
        node = SCENE_NODE.match("[" + section)
        if node is not None:
            name, parent = node[1], node[2]
            node_path = "." if parent is None else name if parent == "." else f"{parent}/{name}"
            mode = SCENE_MODE.search(section)
            own = int(mode[1]) if mode else 0
            inherited = parent is not None and disabled.get(parent, False)
            disabled[node_path] = own == DISABLED or (own != 1 and inherited)
            if 'type="TabContainer"' in section.split("\n", 1)[0]:
                tab_containers.add(node_path)
            if parent in tab_containers:
                yield Hit(path, unescaped(name), line)
            if disabled[node_path]:
                for match in SCENE_TEXT.finditer(section):
                    if is_words(match[1]):
                        yield Hit(path, unescaped(match[1]), line)
        line += section.count("\n")


def main() -> int:
    # The game's project folder (#1101): every path below is relative to it.
    os.chdir(Path(__file__).resolve().parents[1] / "game")
    files = [
        path
        for path in sorted(git_files("*.gd", "*.tscn"))
        if not path.startswith(("tools/", "tests/"))
    ]
    scripts = [parse(path) for path in files if path.endswith(".gd")]
    hits = Flow(scripts).run()
    for script in scripts:
        hits |= set(tab_title_hits(script))
    for path in files:
        if path.endswith(".tscn"):
            hits |= set(scene_hits(path))
    failed = False
    found: dict[tuple[str, str], Hit] = {}
    for hit in sorted(hits, key=lambda hit: (hit.file, hit.line, hit.text)):
        found.setdefault((hit.file, hit.text), hit)
    for key, hit in found.items():
        if key in ALLOWED or key in KNOWN:
            continue
        log.error(
            f"{hit.text!r} is shown to the player without tr(): show it through tr() with a"
            " literal string (AGENTS.md, translations), or, if it's deliberate, allow it with a"
            f" reason in {LISTS}",
            hit.file,
            hit.line,
        )
        failed = True
    for key, issue in KNOWN.items():
        if key not in found:
            log.error(
                f"{key[1]!r} (#{issue}) no longer reaches the player hard-coded:"
                f" take it off KNOWN in {LISTS}",
                key[0],
            )
            failed = True
    for key, reason in ALLOWED.items():
        if not reason.strip():
            log.error(f"{key[1]!r} is allowed without a reason: give one in {LISTS}", key[0])
            failed = True
        if key not in found:
            log.error(f"{key[1]!r} is no longer shown: take it off ALLOWED in {LISTS}", key[0])
            failed = True
    if "--list" in sys.argv[1:]:
        for (file, text), hit in found.items():
            print(f"{file}\t{hit.line}\t{text!r}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
