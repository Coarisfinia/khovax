"""A model script's gait values, set from its arguments (#1524), so the gait sweep
(sweep_gait.py) can build it over a grid of them:

    ... --python packages/game-models/<name>.py -- <out.glb> [NAME=value ...]

Only the names the script offers can be set, each to a value of its default's type. Without any,
the script builds exactly as committed (the rebuild check)."""

import sys


def arguments(values, names):
    """The output path after the `--`, with each `NAME=value` after it set in `values` (the
    script's globals) when `names` offers it; anything else is refused."""
    args = sys.argv[sys.argv.index("--") + 1:]
    for arg in args[1:]:
        name, _, value = arg.partition("=")
        if name not in names or not value:
            raise SystemExit("unknown gait value %r: this script takes %s" % (arg, ", ".join(names)))
        kind = type(values[name])
        try:
            values[name] = kind(value)
        except ValueError:
            raise SystemExit("%s takes a %s, not %r" % (name, kind.__name__, value)) from None
        print("GAIT %s=%s" % (name, values[name]))
    return args[0]
