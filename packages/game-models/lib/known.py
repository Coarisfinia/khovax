"""A check's known failures (check_clearance.py, check_volume.py, check_connectivity.py,
check_motion.py): a clip that still fails today waits in the check's KNOWN dict, {(model, clip):
the issue that fixes it}, prints its numbers and doesn't fail the check. The list only shrinks: a
clip on it that passes fails the check until it's taken off."""


def judge(known, model, line, clip=None):
    """The report line `<verdict> <clip>: ...` as printed, and whether it fails the check: a known
    failure doesn't, and a known one that passes does. `clip` names the line's entry when its
    second word doesn't (a motion check's join)."""
    verdict, named = line.split(" ", 2)[:2]
    issue = known.get((model, clip or named.rstrip(":")))
    if issue is None:
        return line, verdict == "FAIL"
    if verdict == "FAIL":
        return "known %s (#%d)" % (line, issue), False
    return "FAIL %s, which KNOWN still lists (#%d): take it off" % (line, issue), True
