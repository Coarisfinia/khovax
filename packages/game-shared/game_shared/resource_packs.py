"""The default resource pack's manifest (#1860), as the checks read it: the pack that describes the
game's own resources, which ResourcePacks (slices/resource_packs/meta/) resolves every lookup
through. Paths are relative to the game's project folder, packages/game, where res:// starts.
"""

import json
import re
from pathlib import Path

# The default pack's manifest; its files are named from res://, the pack's root.
MANIFEST = Path("slices/resource_packs/data/default.jsonc")
# A JSON string (kept), a // line comment or a /* */ block comment (dropped, its line breaks kept),
# as the game's Jsonc.strip reads them.
JSONC_TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', re.DOTALL)


def strip_jsonc(text: str) -> str:
    """`text` without its comments, outside strings only, keeping every line break."""

    def kept(match: re.Match[str]) -> str:
        token = match.group(0)
        return token if token.startswith('"') else "\n" * token.count("\n")

    return JSONC_TOKEN.sub(kept, text)


def read_manifest(path: Path = MANIFEST) -> dict[str, object]:
    """The manifest at `path` as a JSON object; ValueError when it isn't one, or names a key twice
    (which JSON would silently let the last one win)."""

    def unique(pairs: list[tuple[str, object]]) -> dict[str, object]:
        keys = [key for key, _ in pairs]
        twice = sorted({key for key in keys if keys.count(key) > 1})
        if twice:
            raise ValueError(f"names {', '.join(twice)} twice")
        return dict(pairs)

    data = json.loads(strip_jsonc(path.read_text(encoding="utf-8")), object_pairs_hook=unique)
    if not isinstance(data, dict):
        raise ValueError("isn't a JSON object")
    return data


def textures(manifest: dict[str, object]) -> dict[str, str]:
    """The manifest's textures, each file by its id, leaving out entries that aren't text."""
    raw = manifest.get("textures")
    entries = raw if isinstance(raw, dict) else {}
    return {key: value for key, value in entries.items() if isinstance(value, str)}
