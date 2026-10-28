"""The checks' summary mode (#1524): with `--summary`, the motion, ground and clearance checks
print one line per clip and limit it misses, and how far, instead of their full report, as plain
lines (never annotations), so an agent or the gait sweep (sweep_gait.py) reads a few short lines
rather than long logs:

    MOTION FAIL Run jitter 18.20 > 15.00 deg/frame^2 (by 3.20)
    MOTION ok: Attack Faint Hit Idle Walk
    MOTION CHECK: FAIL (at 30 fps)

A miss without a number (a foot that moves no mesh, a clip starting late) prints only its
measure. sweep_gait.py reads the lines back with LINE."""

import re

# A summary's miss line: the check, the clip, the measure, and when it has numbers, the value, the
# side it misses on, the limit and its unit.
LINE = re.compile(r"^(?P<check>[A-Z]+) FAIL (?P<clip>\S+) (?P<measure>\S+)"
                  r"(?: (?P<value>-?[\d.]+) (?P<side>[<>]) (?P<limit>-?[\d.]+)(?: (?P<unit>\S+))?)?")


class Misses:
    """The limits a check's clips miss, collected as it measures them."""

    def __init__(self):
        self.found = []

    def above(self, clip, measure, value, limit, unit, scale=1.0):
        """Records a miss when `value` is above `limit` (both shown times `scale`, in `unit`)."""
        if value > limit:
            self.found.append((clip, measure, value * scale, ">", limit * scale, unit))

    def below(self, clip, measure, value, limit, unit, scale=1.0):
        """Records a miss when `value` is below `limit`."""
        if value < limit:
            self.found.append((clip, measure, value * scale, "<", limit * scale, unit))

    def flag(self, clip, measure):
        """Records a miss that has no number."""
        self.found.append((clip, measure, None, None, None, None))

    def clips(self):
        return {clip for clip, *_rest in self.found}


def shown(value, limit):
    """`value` and `limit` with two decimals, or as many more as tell a value just past its limit
    from it."""
    for digits in range(2, 7):
        if round(value, digits) != round(limit, digits):
            break
    return "%.*f" % (digits, value), "%.*f" % (digits, limit), "%.*f" % (digits, abs(value - limit))


def lines(misses, clips):
    """The summary, for its check to print after its name: a line per miss, then the clips that
    miss nothing on one line, unless a miss of the whole model (a wisp that can't be measured)
    kept the clips from being checked at all."""
    out = []
    for clip, measure, value, side, limit, unit in misses.found:
        if value is None:
            out.append("FAIL %s %s" % (clip, measure))
        else:
            value_text, limit_text, by = shown(value, limit)
            out.append("FAIL %s %s %s %s %s %s (by %s)" % (clip, measure, value_text, side, limit_text, unit, by))
    passing = sorted(set(clips) - misses.clips())
    if passing and misses.clips() <= set(clips):
        out.append("ok: " + " ".join(passing))
    return out
