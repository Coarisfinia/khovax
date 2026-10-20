"""A GDScript source split into its code, strings and comments, for the checks that read scripts
(#926, #1038).

A comment is a # outside a string, up to the line's end. A string is "…" or '…', which end at
their line, or the triple-quoted \"\"\"…\"\"\" and '''…''', which may span lines; a backslash
escapes the next character in every one of them (raw strings too, as Godot reads them, so an
escaped quote never ends one). The prefix of a raw (r), StringName (&) or NodePath (^) string stays
code. Line breaks are never part of a comment, so a script without its comments keeps its line
numbers.
"""

from collections.abc import Iterator
from dataclasses import dataclass
from enum import Enum, auto


class Kind(Enum):
    CODE = auto()
    STRING = auto()
    COMMENT = auto()


@dataclass(frozen=True)
class Token:
    kind: Kind
    text: str


def tokens(source: str) -> Iterator[Token]:
    """The source in order, as runs of code, strings and comments that join back into it."""
    code_start = 0
    i = 0
    while i < len(source):
        char = source[i]
        if char == "#":
            end = source.find("\n", i)
            end = len(source) if end == -1 else end
            kind = Kind.COMMENT
        elif char in "\"'":
            end = _string_end(source, i)
            kind = Kind.STRING
        else:
            i += 1
            continue
        if code_start < i:
            yield Token(Kind.CODE, source[code_start:i])
        yield Token(kind, source[i:end])
        code_start = i = end
    if code_start < len(source):
        yield Token(Kind.CODE, source[code_start:])


def without_comments(source: str) -> str:
    """The source with every comment removed, its code and strings untouched."""
    return "".join(token.text for token in tokens(source) if token.kind != Kind.COMMENT)


def _string_end(source: str, start: int) -> int:
    """Where the string opening at `start` ends: after its closing quote, or, left open, at its
    line's end (one quote) or the source's end (three)."""
    quote = source[start] * 3 if source.startswith(source[start] * 3, start) else source[start]
    i = start + len(quote)
    while i < len(source):
        if source[i] == "\\":
            i += 2
        elif source.startswith(quote, i):
            return i + len(quote)
        elif source[i] == "\n" and len(quote) == 1:
            return i
        else:
            i += 1
    return len(source)
