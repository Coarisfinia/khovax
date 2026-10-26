"""A check's known failures (check_clearance.py, check_volume.py): a clip that still fails today
waits in the check's KNOWN dict, {(model, clip): the issue that fixes it}, prints its numbers and
doesn't fail the check. The list only shrinks: a clip on it that passes fails the check until it's
taken off."""


def judge(known, model, line):
    """The report line `<verdict> <clip>: ...` as printed, and whether it fails the check: a known
    failure doesn't, and a known one that passes does."""
    verdict, clip = line.split(" ", 2)[:2]
    issue = known.get((model, clip.rstrip(":")))
    if issue is None:
        return line, verdict == "FAIL"
    if verdict == "FAIL":
        return "known %s (#%d)" % (line, issue), False
    return "FAIL %s, which KNOWN still lists (#%d): take it off" % (line, issue), True
