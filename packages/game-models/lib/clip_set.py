"""The clips every creature model carries (owner, #1157): one name per state the game plays a
creature in. It is the one place they're named: `clips.animate` refuses to build a creature
without one of them, and `check_clip_set.py` fails CI on a committed creature model that lacks
one. A clip every creature gains is added here, and each creature's build then makes it.

Plain Python, without Blender, so the check reads it outside Blender too."""

# The long attack (#1158) is three clips the game plays in turn: its wind-up, the loop it holds
# for as long as the attack lasts, and its release.
# Feed (#1203) is its grazing and drinking, one clip for both, and Sleep (#1229) the loop a sleeping
# wild monster lies in.
CREATURE = ("Idle", "Walk", "Run", "Attack", "Hit", "Faint", "ChannelStart", "Channel", "ChannelEnd", "Feed",
            "Sleep")


def missing(names):
    """The creature clips that `names` lacks, in the set's order."""
    return [clip for clip in CREATURE if clip not in names]
