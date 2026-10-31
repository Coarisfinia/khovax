"""A translation catalogue's gaps against the template (#1968): the texts of translations/khovax.pot
a language's .po leaves untranslated, which the game shows in English, and the texts it holds that
the template no longer has, translated or not. resource_packs_check.py warns about both for every
catalogue the default pack lists; neither fails CI, since a language may well be incomplete.

A text is its context (msgctxt, or None) and its msgid. It counts as translated, as Godot reads a
catalogue, only when every msgstr is filled and the entry isn't fuzzy. The header (the empty msgid)
and obsolete entries (#~) are no texts.
"""

import re
from dataclasses import dataclass

# A keyword line: msgctxt, msgid, msgid_plural or msgstr (msgstr[n] for a plural), then a string.
KEYWORD = re.compile(r'^(msgctxt|msgid|msgid_plural|msgstr(?:\[[0-9]+\])?)\s+"(.*)"$')
# A string continuing the keyword above it.
CONTINUED = re.compile(r'^"(.*)"$')
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}
# How many texts a warning names before it says how many more there are.
NAMED = 5

type Text = tuple[str | None, str]


@dataclass(frozen=True)
class Entry:
    """One text of a catalogue or the template, and whether it's translated."""

    context: str | None
    text: str
    translated: bool


def unquoted(body: str) -> str:
    """A .po string's text, without its escapes."""
    return re.sub(r"\\(.)", lambda match: ESCAPES.get(match[1], match[0]), body)


def entries(source: str) -> list[Entry]:
    """The texts of the catalogue or template `source`, in its order."""
    found: list[Entry] = []
    fields: dict[str, str] = {}
    fuzzy = False
    key = ""

    def close() -> None:
        nonlocal fields, fuzzy, key
        if fields.get("msgid"):
            strings = [value for name, value in fields.items() if name.startswith("msgstr")]
            done = not fuzzy and bool(strings) and all(strings)
            # An empty context is no context, as Godot reads a catalogue.
            found.append(Entry(fields.get("msgctxt") or None, fields["msgid"], done))
        fields, fuzzy, key = {}, False, ""

    for line in source.splitlines():
        line = line.strip()
        started = any(name.startswith("msgstr") for name in fields)
        keyword = KEYWORD.match(line)
        # An entry ends at a blank line, or where the next one's comments or keywords begin.
        begins = line.startswith("#") or bool(keyword and keyword[1] in ("msgctxt", "msgid"))
        if not line or (started and begins):
            close()
        if line.startswith("#,") and "fuzzy" in line[2:].replace(",", " ").split():
            fuzzy = True
        elif keyword:
            key = keyword[1]
            fields[key] = unquoted(keyword[2])
        elif (continued := CONTINUED.match(line)) and key:
            fields[key] += unquoted(continued[1])
    close()
    return found


def gaps(template: list[Entry], catalogue: list[Entry]) -> tuple[list[Text], list[Text]]:
    """The template's texts the catalogue leaves untranslated, in the template's order, and the
    catalogue's texts the template doesn't have, translated or not, in the catalogue's order."""
    wanted = {(entry.context, entry.text) for entry in template}
    done = {(entry.context, entry.text) for entry in catalogue if entry.translated}
    missing = [(entry.context, entry.text) for entry in template if (entry.context, entry.text) not in done]
    stale = [(entry.context, entry.text) for entry in catalogue if (entry.context, entry.text) not in wanted]
    return missing, stale


def named(texts: list[Text]) -> str:
    """The first texts of `texts`, each with its context, and how many more there are."""
    shown = [text if context is None else f"{text} ({context})" for context, text in texts[:NAMED]]
    more = len(texts) - NAMED
    return "; ".join(shown) + (f"; and {more} more" if more > 0 else "")


def report(locale: str, template: str, catalogue: str) -> list[str]:
    """The warnings about the catalogue of `locale` against the template, both as text."""
    wanted = entries(template)
    missing, stale = gaps(wanted, entries(catalogue))
    warnings: list[str] = []
    if missing:
        warnings.append(
            f"translation {locale} leaves {len(missing)} of {len(wanted)} texts untranslated, "
            f"so they show in English: {named(missing)}"
        )
    if stale:
        warnings.append(
            f"translation {locale} holds {len(stale)} texts the template no longer has: {named(stale)}"
        )
    return warnings
