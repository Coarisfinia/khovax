"""The lists hardcoded_texts.py reads (#1693), each entry named by its file (from packages/game)
and its text: the hits waiting for the issue that moves them over to tr(), and the deliberate
exceptions."""

# The hits that exist today, each with its issue. A hit fixed must come off, so the list only
# shrinks; a new hit never goes on it.
KNOWN: dict[tuple[str, str], int] = {
}  # fmt: skip

# Deliberate exceptions, each with its reason (e.g. the name of a language, which stays in that
# language).
ALLOWED: dict[tuple[str, str], str] = {}
