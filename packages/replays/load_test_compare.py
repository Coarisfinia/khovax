"""Compares two headless load test reports (packages/game/tools/godot/load_test.gd, #101) for CI
(#303): this branch's and, on a pull request, its base's, both measured in the same job on the
same runner. Prints a Markdown table for the job summary, and fails when this branch's mean tick is
more than SLOWER times the base's (plus a small floor, since a tick is microseconds and runners
jitter).

    uv run --locked packages/replays/load_test_compare.py <this branch's report> [<base's report>]
"""

import re
import sys
from pathlib import Path

SLOWER = 1.5
FLOOR_US = 50

MEAN = re.compile(r"^ *tick: mean ([0-9]+\.[0-9]) us", re.MULTILINE)
FEATURE = re.compile(r"^ *feature ([a-z0-9_]+): ([0-9]+\.[0-9]) us per tick$", re.MULTILINE)
END_STATE = re.compile(r"^end state hash -?[0-9]+, same in both passes$", re.MULTILINE)


def mean_of(report: str) -> str | None:
    """The mean tick in microseconds; None unless the report has exactly one."""
    means = MEAN.findall(report)
    return means[0] if len(means) == 1 else None


def features_of(report: str) -> list[tuple[str, str]]:
    """Every feature's share of a tick in microseconds, in the report's order."""
    return FEATURE.findall(report)


def main(head_path: str, base_path: str = "") -> int:
    head = Path(head_path).read_text(encoding="utf-8")
    if not END_STATE.search(head):
        print(
            "The load test didn't end with both passes in the same state: it failed, or the"
            " simulation isn't deterministic."
        )
        return 1
    head_mean = mean_of(head)
    if head_mean is None:
        print("The load test's report has no mean tick.")
        return 1

    base_file = Path(base_path) if base_path else None
    base = base_file.read_text(encoding="utf-8") if base_file and base_file.is_file() else ""
    base_mean = mean_of(base)
    if base_mean is None:
        print("### Load test")
        print()
        print("| | This branch |")
        print("|---|---|")
        print(f"| A tick, mean | {head_mean} µs |")
        for feature, share in features_of(head):
            print(f"| Feature {feature} | {share} µs |")
        return 0

    base_shares = dict(reversed(features_of(base)))
    print("### Load test, against the base")
    print()
    print("| | Base | This branch |")
    print("|---|---|---|")
    print(f"| A tick, mean | {base_mean} µs | {head_mean} µs |")
    for feature, share in features_of(head):
        print(f"| Feature {feature} | {base_shares.get(feature, '-')} µs | {share} µs |")

    if float(head_mean) > float(base_mean) * SLOWER + FLOOR_US:
        print()
        print(
            f"**The simulation got slower:** a mean tick of {head_mean} µs against the base's"
            f" {base_mean} µs."
        )
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
