"""Which models CI's model checks look at (#2031). For now the gate CI has today, to show
test_changed_models.py failing on it: a change anywhere the checks read checks every model, and
the workflow's own changes check none."""

import fnmatch

TODAY = (
    "packages/game-models/*",
    "*.glb",
    "*.glb.import",
    ".github/actions/setup-blender/*",
    "packages/game/slices/*/look/*",
    "packages/game/*.tscn",
    "packages/game/slices/resource_packs/data/*",
)


def select(changed: list[str], is_model_script) -> set[str] | None:
    """The models the changed paths (from the root) check, or None for every model."""
    if any(fnmatch.fnmatchcase(path, pattern) for path in changed for pattern in TODAY):
        return None
    return set()
