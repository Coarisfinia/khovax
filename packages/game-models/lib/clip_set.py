"""The clips every creature model carries (owner, #1157): one name per state the game plays a
creature in. It is the one place they're named: `clips.animate` refuses to build a creature
without one of them, and `check_clip_set.py` fails CI on a committed creature model that lacks
one. A clip every creature gains is added here, and each creature's build then makes it.

Plain Python, without Blender, so the check reads it outside Blender too."""

CREATURE = ("Idle", "Walk", "Run", "Attack", "Hit", "Faint")


def missing(names):
    """The creature clips that `names` lacks, in the set's order."""
    return [clip for clip in CREATURE if clip not in names]
